#!/usr/bin/perl

# FastCGI обрабатывающий запросы в систему:
#  - принимает новые документы
#  - отдает документы

BEGIN {
  use YAML;

  my $cfg;
  if (defined($ARGV[0]) && ($ARGV[0] ne '')) {
    if (-e $ARGV[0]) {
      $cfg = YAML::LoadFile($ARGV[0]);
    } else {
      print STDERR 'Can not exists config file "'.$ARGV[0].'"'."\n";
      exit(1);
    };
  } else {
    print STDERR "I need config file path to command line\n";
    exit(1);
  };

  require $cfg->{'base_path'}.'/libs/proc.pm';

  proc::check_command($cfg);

	$cfg->{'fcgi'}->{'host'} = '127.0.0.1' if (!defined($cfg->{'fcgi'}->{'host'}) || ($cfg->{'fcgi'}->{'host'} eq ''));
	$cfg->{'fcgi'}->{'port'} = '9001' if (!defined($cfg->{'fcgi'}->{'port'}) || ($cfg->{'fcgi'}->{'port'} eq ''));
	$cfg->{'fcgi'}->{'listen_queue'} = 128 if (!defined($cfg->{'fcgi'}->{'listen_queue'}) || ($cfg->{'fcgi'}->{'listen_queue'} eq ''));

	$ENV{FCGI_SOCKET_PATH} = $cfg->{'fcgi'}->{'host'}.":".$cfg->{'fcgi'}->{'port'};
	$ENV{FCGI_LISTEN_QUEUE} = $cfg->{'fcgi'}->{'listen_queue'};

	sub _get_config {
		return $cfg;
	};
}

use strict;
use POSIX;
use CGI::Fast qw/:standard :debug/;
use Sys::Hostname;
use Sys::Syslog;
use Time::HiRes qw(usleep);
use Switch;
use DBI;
use Digest::SHA qw(sha256_base64);
use Crypt::OpenSSL::RSA;
use Crypt::RSA;
use MIME::Base64 qw(encode_base64);
use String::Random;
use LWP::UserAgent;
use Data::Dumper;
use HTML::QRCode;
use URI::Encode qw(uri_encode uri_decode);
use Template;
use utf8;
use Encode qw(encode decode_utf8);

use GPLVote::SignDoc::Client;
#no warnings;

use vars qw($cfg $dbh);

# Получение конфига из блока BEGIN
$cfg = _get_config();

use FCGI::ProcManager::Dynamic;
require $cfg->{'base_path'}.'/libs/proc.pm';
require $cfg->{'base_path'}.'/libs/js.pm';
require $cfg->{'base_path'}.'/libs/db.pm';

# Демонизация
proc::demonize($cfg->{'log_file'}, $cfg->{'pid_file'});

# Инициализация логирования в syslog
Sys::Syslog::setlogsock('unix');
openlog($cfg->{product_name},'ndelay,pid', 'LOG_LOCAL6');

to_syslog("Start...");

# Запуск менеджера рабочих процессов
my $pm = FCGI::ProcManager->new({
	n_processes => $cfg->{fcgi}->{nprocs},
});
$pm->pm_manage;

####### Начало рабочего процесса #######

$dbh = db::check_db_connect($dbh, $cfg->{db}->{host}, $cfg->{db}->{port}, $cfg->{db}->{name}, $cfg->{db}->{user}, $cfg->{db}->{password});

# Начало FastCGI цикла рабочего процесса
while (my $query = new CGI::Fast) {
	$pm->pm_pre_dispatch();

	
  my $result = {
    'status' => 0,
  };

  ########################################
  
  my $site = $cfg->{site};

  # По URI определяем команду
  my $uri = $ENV{'REQUEST_URI'};
  if ($uri =~ /^(.+)\?/) {
    $uri = $1;
  };
  
  switch ($uri) {
    case '/' {
      do_template($query, 'karkas.tpl', { contentsection => 'c_index.tpl' });
    }
    
    case '/petition_sample' {
      # Петиция
      my $qrcode = html_qrcode('signdoc://signdoc-client.gplvote.org/get_doc?id=PUBPETITION1&mode=direct');
      do_template($query, 'karkas.tpl', { contentsection => 'c_petition.tpl', footer => 'b_footer_new.tpl', qrcode => $qrcode });
    }
    case '/petition_sample/ident' {
      # Форма представления
      # Представление - это документ с id="PINFO:<ID публичного документа к которому относится представление>"
      # и массивом из одного элемента в данных.
      # При необходимости выбрать представление для конкретной подписи, выборка идет по условию:
      #  doc_id = "PINFO:<id публичного документа>" AND user_key_id = <user_key_id из подписи документа>
      
      do_template($query, 'karkas.tpl', { contentsection => 'c_petition_person_form.tpl', footer => 'b_footer_new.tpl' });
    }
    case '/petition_sample/ident_sign' {
      # Подписание представления
      my $person_info = decode_utf8($query->param('person_info'));
      
      if (!defined($person_info) || ($person_info eq '')) {
          # Редирект назад на представление
          print $query->redirect('/petition_sample/ident');
      } else {
          # Формируем документ с представлением на подписание
          my $doc = {};
          $doc->{doc_id} = generate_pinfo_doc_id('PUBPETITION1');
          $doc->{dec_data} = '["'.$person_info.'"]';
          $doc->{template} = "HTML\nВаше представление: <b><%data_0%></b>";
          
          $dbh->do('INSERT INTO documents (id, code, doc_data, doc_template) VALUES (?, ?, ?, ?)', undef, $doc->{doc_id}, '', $doc->{dec_data}, $doc->{template});
          $dbh->commit;

          # Формируем QR-код со ссылкой на подписание представления
          my $qrcode = html_qrcode('signdoc://signdoc-client.gplvote.org/get_doc?id='.$doc->{doc_id}.'&mode=direct');
          do_template($query, 'karkas.tpl', { contentsection => 'c_petition_person_sign.tpl', footer => 'b_footer_new.tpl', qrcode => $qrcode });
      };
    }
    case '/petition_sample/signs' {
      # Все подписи
      my $sql = <<SQL;
        SELECT 
          s.user_key_id, s.t_sign, docs.doc_data 
        FROM 
          signs s, signs sp, documents docs
        WHERE 
          s.doc_id = ? AND
          sp.doc_id LIKE ? AND
          s.user_key_id = sp.user_key_id AND
          docs.id = sp.doc_id
        ORDER BY 1, 2
SQL
      my $c = $dbh->prepare($sql);
      $c->execute('PUBPETITION1', 'PINFO:PUBPETITION1:%');
      my @list;
      my $prev_sign = {user_key_id => ''};
      while (my $sign = $c->fetchrow_hashref()) {
        my $doc_data = js::from_json($sign->{doc_data});
        $sign->{person_info} = encode('UTF-8', $doc_data->[0]);
        $sign->{t_sign} =~ s/\.[0-9]+//g;
        delete($sign->{doc_data});
        
        my $sep = '';
        $sep = "<br>\n" if defined($prev_sign->{person_info}) && ($prev_sign->{person_info} ne '');
        if ($prev_sign->{user_key_id} ne $sign->{user_key_id}) {
          push(@list, $prev_sign) if defined($prev_sign->{user_key_id}) && ($prev_sign->{user_key_id} ne '');
          $prev_sign = $sign;
        } else {
          $prev_sign->{person_info} = $prev_sign->{person_info}.$sep.$sign->{person_info};
        };
      };
      push(@list, $prev_sign) if defined($prev_sign->{person_info}) && ($prev_sign->{person_info} ne '');
      $c->finish;
      
      do_template($query, 'karkas.tpl', { contentsection => 'c_petition_signs.tpl', footer => 'b_footer_new.tpl', list => \@list });
    }
    
    
    
    case '/vote_sample' {
      do_template($query, 'karkas.tpl', { contentsection => 'c_vote.tpl' });
    }
    case '/vote_sample/choise' {
      my $choise = $query->param('v');
      
      # Формируем QR-код для выбранного варианта
      my $qrcode = html_qrcode('signdoc://signdoc-client.gplvote.org/get_doc?id=PUBVOTE1:'.$choise.'&mode=direct');
      do_template($query, 'karkas.tpl', { contentsection => 'c_vote_choise.tpl', qrcode => $qrcode, choise => $choise });
    }
    case '/vote_sample/ident' {
      my $choise = decode_utf8($query->param('v'));
      do_template($query, 'karkas.tpl', { contentsection => 'c_vote_person_form.tpl', footer => 'b_footer_new.tpl', choise => $choise });
    }
    case '/vote_sample/ident_sign' {
      # Подписание представления
      my $person_info = decode_utf8($query->param('person_info'));
      my $choise = decode_utf8($query->param('v'));
      
      if (!defined($person_info) || ($person_info eq '')) {
          # Редирект назад на представление
          print $query->redirect('/vote_sample/ident?v='.$choise);
      } else {
          # Формируем документ с представлением на подписание
          my $doc = {};
          $doc->{doc_id} = generate_pinfo_doc_id('PUBVOTE1:'.$choise);
          $doc->{dec_data} = '["'.$person_info.'"]';
          $doc->{template} = "HTML\nВаше представление: <b><%data_0%></b>";
          
          $dbh->do('INSERT INTO documents (id, code, doc_data, doc_template) VALUES (?, ?, ?, ?)', undef, $doc->{doc_id}, '', $doc->{dec_data}, $doc->{template});
          $dbh->commit;

          # Формируем QR-код со ссылкой на подписание представления
          my $qrcode = html_qrcode('signdoc://signdoc-client.gplvote.org/get_doc?id='.$doc->{doc_id}.'&mode=direct');
          do_template($query, 'karkas.tpl', { contentsection => 'c_vote_person_sign.tpl', footer => 'b_footer_new.tpl', qrcode => $qrcode, choise => $choise });
      };
    }
    case '/vote_sample/signs' {
      # Загружаем голоса за варианты, учитывая только последний голос. Считаем общее количество голосов за каждый вариант.
      my $sql = <<SQL;
        SELECT
          s.t_sign,
          s.user_key_id,
          pdocs.doc_data,
          docs.doc_data as vote_data
        FROM
          signs s,
          signs sp,
          documents pdocs,
          documents docs
        WHERE
          s.doc_id LIKE ? AND
          s.t_sign = 
            ( SELECT MAX(ss.t_sign)
              FROM signs ss
              WHERE ss.user_key_id = s.user_key_id AND ss.doc_id LIKE ?
            ) AND
          sp.doc_id LIKE 'PINFO:' || s.doc_id || ':%' AND
          s.user_key_id = sp.user_key_id AND
          pdocs.id = sp.doc_id AND
          docs.id = s.doc_id
        ORDER BY 2, 1
SQL
      my $c = $dbh->prepare($sql);
      $c->execute('PUBVOTE1:%', 'PUBVOTE1:%');
    
      my @list;
      my $choise1 = 0;
      my $choise2 = 0;
      my $choise3 = 0;
      
      my $prev_sign = {user_key_id => ''};
      while (my $sign = $c->fetchrow_hashref()) {
        my $doc_data = js::from_json($sign->{doc_data});
        $sign->{person_info} = encode('UTF-8', $doc_data->[0]);
        $sign->{t_sign} =~ s/\.[0-9]+//g;
        delete($sign->{doc_data});
        
        my $sep = '';
        $sep = "<br>\n" if defined($prev_sign->{person_info}) && ($prev_sign->{person_info} ne '');
        if ($prev_sign->{user_key_id} ne $sign->{user_key_id}) {
          if (defined($prev_sign->{vote_data}) && ($prev_sign->{vote_data} ne '')) {
            my $vote_data = js::from_json($prev_sign->{vote_data});
            $choise1++ if ($vote_data->[0] eq 'Вариант 1');
            $choise2++ if ($vote_data->[0] eq 'Вариант 2');
            $choise3++ if ($vote_data->[0] eq 'Вариант 3');
            $prev_sign->{choise} = encode('UTF-8', $vote_data->[0]);
          };
          
          push(@list, $prev_sign) if defined($prev_sign->{user_key_id}) && ($prev_sign->{user_key_id} ne '');
          $prev_sign = $sign;
        } else {
          $prev_sign->{person_info} = $prev_sign->{person_info}.$sep.$sign->{person_info};
        };
      };
      if (defined($prev_sign->{vote_data}) && ($prev_sign->{vote_data} ne '')) {
        my $vote_data = js::from_json($prev_sign->{vote_data});
        $choise1++ if ($vote_data->[0] eq 'Вариант 1');
        $choise2++ if ($vote_data->[0] eq 'Вариант 2');
        $choise3++ if ($vote_data->[0] eq 'Вариант 3');
        $prev_sign->{choise} = encode('UTF-8', $vote_data->[0]);
        push(@list, $prev_sign);
      };
      $c->finish;
      
      do_template($query, 'karkas.tpl', { contentsection => 'c_vote_signs.tpl', footer => 'b_footer_new.tpl', list => \@list, 
                                          choise1_count => $choise1,
                                          choise2_count => $choise2,
                                          choise3_count => $choise3 });
    }
    
    
    case '/confirm_sample' {
      do_template($query, 'karkas.tpl', { contentsection => 'c_confirm.tpl' });
    }
    case '/confirm_sample/register' {
      my $code;
      if (defined($query->param('code')) && ($query->param('code') ne '')) {
        $code = $query->param('code');
      } else {
        $code = generate_register_code();
      };
    
      my $qrcode = html_qrcode('signreg://signdoc-client.gplvote.org/sign_reg?code='.$code.'&site=test');
      do_template($query, 'karkas.tpl', { contentsection => 'c_confirm_register.tpl', qrcode => $qrcode, code => $code });
    }
    case '/confirm_sample/register_check' {
      my $code = $query->param('code');
    
      my $c = $dbh->prepare('SELECT public_key FROM registrations WHERE code = ?');
      $c->execute($code);
      my ($pub_key) = $c->fetchrow_array;
      $c->finish;

      my $is_register = 0;
      $is_register = 1 if defined($pub_key) && ($pub_key ne '');
    
      do_template($query, 'karkas.tpl', { contentsection => 'c_confirm_register_check.tpl', code => $code, is_register => $is_register });
    }
    case '/confirm_sample/action' {
      my $code = $query->param('code');
      
      my $sr = new String::Random;

      my $doc = {};
      my $tmpl = ['LIST', 'Подтверждаемое действие:', 'Просто заполнение данными'];
      my $data = [];

      push(@{$data}, 'Изменение пароля для кода '.$code);
      push(@{$data}, 'Д' x 300);
      $doc->{type} = "SIGN_REQUEST";
      $doc->{site} = 'test';
      $doc->{dec_data} = js::to_json($data);
      $doc->{template} = join("\n", @{$tmpl});

      $doc->{doc_id} = generate_doc_id();

      $dbh->do('INSERT INTO documents (id, code, doc_data, doc_template) VALUES (?, ?, ?, ?)', undef, 
                $doc->{doc_id}, $code, $doc->{dec_data}, $doc->{template});
      my $dberr = $dbh->errstr;
      $dbh->commit;

      if (defined($dberr) && ($dberr ne '')) {
        warn $dberr;
      };

      my $qrcode = html_qrcode('signdoc://signdoc-client.gplvote.org/get_doc?id='.$doc->{doc_id}.'&mode=direct');
      do_template($query, 'karkas.tpl', { contentsection => 'c_confirm_action.tpl', qrcode => $qrcode, code => $code, doc_id => $doc->{doc_id} });
    }    
    case '/confirm_sample/action_check' {
      my $doc_id = $query->param('doc_id');
      
      my $c = $dbh->prepare('SELECT code, doc_sign FROM documents WHERE id = ?');
      $c->execute($doc_id);
      my ($code, $sign) = $c->fetchrow_array();
      $c->finish;
      
      my $is_confirm = (defined($sign) && ($sign ne ''));
      
      do_template($query, 'karkas.tpl', { contentsection => 'c_confirm_action_check.tpl', is_confirm => $is_confirm, code => $code });
    };
    
    
    
    
    # Далее - интерфейс взаимодействия с приложением
    case '/sign_reg' {
      print $query->header(-type=>'application/json',-charset=>'UTF-8');

      # Получаем регистрацию подписи, проверяем и регистрируем ее

      my $postdata = $query->param('POSTDATA');
      my $reg_doc = js::to_hash($postdata);

      my $c = $dbh->prepare('SELECT id, public_key FROM registrations WHERE code = ?');
      $c->execute($reg_doc->{code});
      my ($id, $pub_key) = $c->fetchrow_array;
      $c->finish;

      if (!defined($pub_key) || ($pub_key eq '')) {
        if (user_sign_is_valid($reg_doc->{public_key}, $reg_doc->{sign}, $reg_doc->{code}, $cfg->{sha256signhash})) {
          $dbh->do('UPDATE registrations SET public_key = ? WHERE id = ?', undef, $reg_doc->{public_key}, $id);
          $dbh->commit;
        } else {
          warn "Bad sign for REGISTER direct ".$reg_doc->{code};
        };
      };
      
      my $result = {status => 0};
      print js::to_json($result);
    }
    case '/sign' {
      print $query->header(-type=>'application/json',-charset=>'UTF-8');

      # Получаем подпись, проверяем и регистрируем ее

      my $postdata = $query->param('POSTDATA');
      my $sign_doc = js::to_hash($postdata);

      get_one_doc($sign_doc);

      my $result = {status => 0};
      print js::to_json($result);
    }
    case '/get_doc' {
      print $query->header(-type=>'application/json',-charset=>'UTF-8');

      my $doc_id = $query->param('id');
      my $mode = $query->param('mode');

      my $c = $dbh->prepare('select * from documents where id = ?');
      $c->execute($doc_id);
      my $doc = $c->fetchrow_hashref();
      $c->finish;

      my $out_doc = {};
      $out_doc->{type} = "SIGN_REQUEST";
      $out_doc->{site} = 'test';
      $out_doc->{template} = $doc->{doc_template};
      $out_doc->{doc_id} = $doc->{id};

      if (defined($mode) && ($mode eq 'direct')) {
	$out_doc->{sign_url} = 'http://signdoc-client.gplvote.org/sign';
      };

      # Если для документа есть код, тогда определяем публичный ключ по коду из документа
      # Если кода нет, значит документ публичный
      if (defined($doc->{code}) && ($doc->{code} ne '')) {
	my $c = $dbh->prepare('SELECT public_key FROM registrations WHERE code = ?');
	$c->execute($doc->{code});
	my ($public_key) = $c->fetchrow_array();
	$c->finish;

	my $pub_key_id = calc_pub_key_id($public_key);

	$out_doc->{user_key_id} = $pub_key_id;

	$out_doc->{data} = encrypt($public_key, $doc->{doc_data});
      } else {
	$out_doc->{dec_data} = $doc->{doc_data};
      };
      
      print js::to_json($out_doc);
    }
    
    else {
      do_template($query, 'karkas.tpl', { contentsection => 'c_bad_request.tpl' });
    };
  };

  ########################################

	$pm->pm_post_dispatch();
};
closelog();

sub to_syslog {
	my ($msg) = @_;

	syslog("alert", $msg);
};

sub html_start {
  my ($query) = @_;
  
  print $query->header(-type=>'text/html',-charset=>'UTF-8');
      print <<HTMLBEG;
<html>
<head>
</head>
<body>
HTMLBEG
}

sub html_finish {
  print <<HTMLEND;
</body>
</html>
HTMLEND
}

sub generate_register_code {
  my ($size) = @_;

  $size = 6 if !defined($size) || ($size eq '');
  
  my $sr = new String::Random;
  $sr->{'A'} = [ 'a'..'z' ];
  
  my $code = '';
  do {
    $code = $sr->randpattern("A" x $size);

    my $c = $dbh->prepare('SELECT id FROM registrations WHERE code = ?');
    $c->execute($code);
    my ($id) = $c->fetchrow_array();
    $c->finish;

    $code = '' if defined($id) && ($id ne '');
  } while($code eq '');

  $dbh->do('INSERT INTO registrations (code) VALUES (?)', undef, $code);
  $dbh->commit;

  return($code);
};


sub generate_doc_id {
  my ($size) = @_;

  $size = 16 if !defined($size) || ($size eq '');

  my $sr = new String::Random;
  $sr->{'A'} = [ 'A'..'Z', 'a'..'z', 0..9 ];

  my $code = '';
  do {
    $code = $sr->randpattern("A" x $size);

    my $c = $dbh->prepare('SELECT id FROM documents WHERE id = ?');
    $c->execute($code);
    my ($id) = $c->fetchrow_array();
    $c->finish;

    $code = '' if defined($id) && ($id ne '');
  } while($code eq '');

  return($code);
};

sub generate_pinfo_doc_id {
  my ($doc_id) = @_;

  my $size = 6;

  my $sr = new String::Random;
  $sr->{'A'} = [ 'A'..'Z', 'a'..'z', 0..9 ];

  my $code = '';
  do {
    $code = 'PINFO:'.$doc_id.':'.$sr->randpattern("A" x $size);

    my $c = $dbh->prepare('SELECT id FROM documents WHERE id = ?');
    $c->execute($code);
    my ($id) = $c->fetchrow_array();
    $c->finish;

    $code = '' if defined($id) && ($id ne '');
  } while($code eq '');

  return($code);
};

sub send_sign_request {
  my ($code, $doc) = @_;

  my $c = $dbh->prepare('SELECT public_key FROM registrations WHERE code = ?');
  $c->execute($code);
  my ($public_key) = $c->fetchrow_array();
  $c->finish;
  
  my $pub_key_id = calc_pub_key_id($public_key);

  $doc->{user_key_id} = $pub_key_id;

  $doc->{data} = encrypt($public_key, $doc->{dec_data});
  delete($doc->{dec_data});

  warn "Send sign request: ".Dumper($doc);
  
  send_doc($doc, '12345678');
};

sub get_user_key_id {
  my ($code) = @_;

  my $c = $dbh->prepare('SELECT public_key FROM registrations WHERE code = ?');
  $c->execute($code);
  my ($public_key) = $c->fetchrow_array();
  $c->finish;

  return calc_pub_key_id($public_key);
};

sub send_sign_confirm {
  my ($code, $doc) = @_;

  my $c = $dbh->prepare('SELECT public_key FROM registrations WHERE code = ?');
  $c->execute($code);
  my ($public_key) = $c->fetchrow_array();
  $c->finish;

  my $pub_key_id = calc_pub_key_id($public_key);

  $doc->{user_key_id} = $pub_key_id;

  send_doc($doc, '12345678');
};

sub get_all_docs {
  get_docs('test', '12345678', \&get_one_doc);
};

sub get_one_doc {
  my ($doc) = @_;

  switch ($doc->{type}) {
    case 'REGISTER' {
      my $c = $dbh->prepare('SELECT id, public_key FROM registrations WHERE code = ?');
      $c->execute($doc->{code});
      my ($id, $pub_key) = $c->fetchrow_array;
      $c->finish;

      if (!defined($pub_key) || ($pub_key eq '')) {
        if (user_sign_is_valid($doc->{public_key}, $doc->{sign}, $doc->{code}, $cfg->{sha256signhash})) {
          $dbh->do('UPDATE registrations SET public_key = ? WHERE id = ?', undef, $doc->{public_key}, $id);
          $dbh->commit;
        } else {
          warn "Bad sign for REGISTER ".$doc->{code};
        };
      };
    };
    case 'SIGN' {
      my $c = $dbh->prepare('SELECT id, doc_sign, doc_data, doc_template, code FROM documents WHERE id = ?');
      $c->execute($doc->{doc_id});
      my ($id, $sign, $doc_data, $doc_template, $code) = $c->fetchrow_array;
      $c->finish;

      if (defined($code) && ($code ne '')) {
	if (!defined($sign) || ($sign eq '')) {
	  my $c = $dbh->prepare('SELECT public_key FROM registrations WHERE code = ?');
	  $c->execute($code);
	  my ($pub_key) = $c->fetchrow_array;
	  $c->finish;

	  if (user_sign_is_valid($pub_key, $doc->{sign}, $doc->{site}.":".$doc->{doc_id}.":".$doc_data.":".$doc_template, $cfg->{sha256signhash})) {
	    $dbh->do('UPDATE documents SET doc_sign = ?, signed = ? WHERE id = ?', undef, $doc->{sign}, 1, $doc->{doc_id});
	    $dbh->commit;
	  } else {
	    warn "Bad SIGN for document ".$doc->{doc_id};
	  };
	};
      } else {
        # Публичный документ
        my $pub_key = $doc->{public_key};
        my $pub_key_id = calc_pub_key_id($pub_key);
      
        # Проверяем нет-ли уже подписи для данного документа от данного пользователя. Если есть - игнорируем.
        $c = $dbh->prepare('SELECT id FROM signs WHERE doc_id = ? AND user_key_id = ?');
        $c->execute($doc->{doc_id}, $pub_key_id);
        my ($sign_id) = $c->fetchrow_array();
        $c->finish;

        if (!defined($sign_id) || ($sign_id eq '')) {
          if (user_sign_is_valid($pub_key, $doc->{sign}, $doc->{site}.":".$doc->{doc_id}.":".$doc_data.":".$doc_template, $cfg->{sha256signhash})) {
            $dbh->do('INSERT INTO signs (doc_id, user_key_id, public_key, sign) VALUES (?, ?, ?, ?)', undef, $doc->{doc_id}, $pub_key_id, $pub_key, $doc->{sign});
            $dbh->commit;
          } else {
            warn "Bad SIGN for document ".$doc->{doc_id};
          };
        };
      };
    };
  };
};

sub do_template
{
    my ($query, $karkas, $prms) = @_;

    my $vars = {
        env => \ %ENV,
        header => 'b_header.tpl',
        contentsection => 'c_index.tpl',
        footer => 'b_footer.tpl',
        cfg => $cfg,
    };

    foreach my $k (keys %$prms)
    {
        $vars->{$k} = $prms->{$k};
    };

    my $include_path = $cfg->{tmpl_path};

    my $out;
    my $tt = Template->new({
        START_TAG       => quotemeta('<?'),
	END_TAG         => quotemeta('?>'),
	INCLUDE_PATH    => $include_path,
	INTERPOLATE     => 0,
	AUTO_RESET      => 1,
	ERROR           => '_error',
	EVAL_PERL       => 1,
	CACHE_SIZE      => 1024,
	COMPILE_EXT     => '.tpl',
	COMPILE_DIR     => '/var/tmp/tt2cache',
	LOAD_PERL       => 1,
	RECURSION       => 1,
	OUTPUT          => \ $out,
    });

    my $ttresult = $tt->process($karkas, $vars);

    print $query->header(-type=>'text/html',-charset=>'UTF-8');

    print "\n";
    print $out;
};

sub html_qrcode {
    my ($data) = @_;
    
    return('<table><tr><td align="center"><a href="'.$data.'" class="qrbutton"></a></td></tr><tr><td>'.HTML::QRCode->new->plot($data).'</td></tr></table>');
};
