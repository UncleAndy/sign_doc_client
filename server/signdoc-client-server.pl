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
use MIME::Base64;
use String::Random;
use LWP::UserAgent;
use Data::Dumper;
use utf8;
use Encode qw(encode);

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

  print $query->header(-type=>'text/html',-charset=>'UTF-8');
      print <<HTMLBEG;
<html>
<head>
</head>
<body>
HTMLBEG

  # По URI определяем команду
  my $uri = $ENV{'REQUEST_URI'};
  if ($uri =~ /^(.+)\?/) {
    $uri = $1;
  };
  
  switch ($uri) {
    case '/' {

      print <<HTML;
  <h2>Тестовый сайт клиента для системы подписания документов</h2>
  
  <p>Данный сайт представляет из себя тестовую площадку для проверки работы системы подписания документов на
  основе мобильного приложения</p>

  <h3>Установка приложения на смартфон</h3>

  <p>Для установки мобильного приложения необходим смартфон на Android с возможностью подключения к интернет.<br>
  1. Необходимо разрешить в смартфоне "Настройки"->"Безопасность"->"Установка приложений из неизвестных источников";<br>
  2. В смартфоне по <a href="http://ru.gplvote.org/signdoc.apk">ссылке</a> скачиваем приложение. Если не хотите скачивать его с нащего сайта, вы можете <a href="https://play.google.com/apps/testing/org.gplvote.signdoc">присоедениться к официальному тестированию через Google Play</a>;<br>
  3. В смартфоне щелкаем на скаченный файл приложения и на запрос об установке отвечаем утвердительно;<br>
  4. После установки запускаем приложение, нажимаем "Инициализация приложения" и на запрос вводим пароль, который будет использоваться
  для шифрования вашего секретного ключа. Сейчас к паролю не предъявляется никаких требований по его длине и качеству;
  </p>

  <h3>Использование данного сайта для тестирования</h3>

  <h4>Регистрация своей электронной подписи на сайте</h4>
  <p>
  1. Переходим на страницу <a href="/register">"Регистрация электронной подписи"</a>;<br>
  2. На смартфоне нажимаем кнопку "Регистрация на сайте";<br>
  3. На смартфоне в приложение вводим "Имя сайта" и "Код" (которые покажутся на странице "Регистрация электронной подписи" сайта) в соответствующие поля и жмем кнопку "Готово";<br>
  4. На странице данного сайта "Проверка регистрации подписи по этому коду" (ссылка доступна на странице регистрации подписи) проверяем состояние регистрации подписи (если не зарегистрирована, периодически обновляем страницу);<br>
  </p>
  <h4>Инициирование отправки документа на подписание</h4>
  <p>
  1. Переходим по ссылке "Генерация случайного документа на подписание";
  </p>
  <h4>Подписание документа и проверка подписи</h4>
  <p>
  1. На смартфоне в приложении жмем на кнопку "Проверить новые документы";<br>
  2. На смартфоне должен отобразиться диалог подписания данного документа со случайными данными;<br>
  3. На смартфоне выбираем вариант "Подписать";<br>
  4. На сайте переходим на страницу "Проверка списока документов" и смотрим статус документов;<br>
  5. Можно опять вернуться к странице "Генерация случайного документа на подписание";
  </p>
  
  <a href="/register">Регистрация электронной подписи</a><br>
HTML
    }
    case '/register' {
      my $code = generate_register_code();
    
      print <<HTML;
  Имя сайта: <b>test</b><br>
  Код: <b>$code</b><br>
  <br>
  <a href="/register_check?code=$code" target="_blank">Проверка регистрации подписи по этому коду</a><br>
HTML
    }
    case '/register_check' {
      my $code = $query->param('code');

      get_all_docs();
      
      my $c = $dbh->prepare('SELECT public_key FROM registrations WHERE code = ?');
      $c->execute($code);
      my ($public_key) = $c->fetchrow_array();
      $c->finish;
      
      if (defined($public_key) && ($public_key ne '')) {
        print <<HTML;
          Регистрация подписи для кода $code прошла успешно<br>
          <br>
          <a href="/sign_request?code=$code">Генерация случайного документа на подписание</a><br>
          <a href="/sign_big_request?code=$code">Генерация большого документа на подписание</a><br>
          <a href="/sign_bad_template_request?code=$code">Генерация документа на подписание с неполным шаблоном</a><br>
HTML
      } else {
        print <<HTML;
          Электронная подпись для кода $code пока не зарегистрирована<br>
          <br>
          <a href="/register">Регистрация электронной подписи</a><br>
HTML
      };
    }
    case '/sign_request' {
      my $code = $query->param('code');

      my $sr = new String::Random;
      
      my $doc = {};
      my $tmpl = ['LIST', 'Первые данные документа', 'Вторые данные докумнта', 'Третьи данные документа', 'Текст: раз два три'];
      my $data = [];

      push(@{$data}, 'Данные с '.$sr->randpattern("cccnnn"));
      push(@{$data}, 'Данные с '.$sr->randpattern("cccnnn"));
      push(@{$data}, 'Данные с '.$sr->randpattern("cccnnn"));
      push(@{$data}, 'Текст документа');
      $doc->{type} = "SIGN_REQUEST";
      $doc->{site} = 'test';
      $doc->{dec_data} = js::to_json($data);
      $doc->{template} = join("\n", @{$tmpl});

      $doc->{doc_id} = generate_doc_id();
      
      $dbh->do('INSERT INTO documents (id, code, doc_data, doc_template) VALUES (?, ?, ?, ?)', undef, $doc->{doc_id}, $code, $doc->{dec_data}, $doc->{template});
      my $dberr = $dbh->errstr;
      $dbh->commit;

      if (defined($dberr) && ($dberr ne '')) {
        print "Ошибка БД при создании нового документа<br>";
        warn $dberr;
      } else {
        send_sign_request($code, $doc);
      };

      print <<HTML
Документ для подписания отправлен. Проверьте новые документы в мобильно приложении<br>
<br>
<a href="/docs_list?code=$code">Проверка списка документов</a><br>
HTML
    }
    case '/sign_big_request' {
      my $code = $query->param('code');

      my $sr = new String::Random;

      my $doc = {};
      my $tmpl = ['LIST', 'Первые данные документа', 'Вторые данные докумнта', 'Третьи данные документа', 'Линк', 'Большой текст'];
      my $data = [];

      push(@{$data}, 'Данные с '.$sr->randpattern("cccnnn"));
      push(@{$data}, 'Данные с '.$sr->randpattern("cccnnn"));
      push(@{$data}, 'Данные с '.$sr->randpattern("cccnnn"));
      push(@{$data}, '<a href="html://gplvote.org/">Проверка ссылки на внешний ресурс</a>');
      push(@{$data}, "Большой текст документа\n" x 20);
      $doc->{type} = "SIGN_REQUEST";
      $doc->{site} = 'test';
      $doc->{dec_data} = js::to_json($data);
      $doc->{template} = join("\n", @{$tmpl});

      $doc->{doc_id} = generate_doc_id();

      $dbh->do('INSERT INTO documents (id, code, doc_data, doc_template) VALUES (?, ?, ?, ?)', undef, $doc->{doc_id}, $code, $doc->{dec_data}, $doc->{template});
      my $dberr = $dbh->errstr;
      $dbh->commit;

      if (defined($dberr) && ($dberr ne '')) {
        print "Ошибка БД при создании нового документа<br>";
        warn $dberr;
      } else {
        send_sign_request($code, $doc);
      };

      print <<HTML
Документ для подписания отправлен. Проверьте новые документы в мобильно приложении<br>
<br>
<a href="/docs_list?code=$code">Проверка списка документов</a><br>
HTML
    }
    case '/sign_bad_template_request' {
      my $code = $query->param('code');

      my $sr = new String::Random;

      my $doc = {};
      my $tmpl = ['LIST', 'Первые данные документа', 'Вторые данные докумнта' ];
      my $data = [];

      push(@{$data}, 'Данные с '.$sr->randpattern("cccnnn"));
      push(@{$data}, 'Данные с '.$sr->randpattern("cccnnn"));
      push(@{$data}, 'Данные с '.$sr->randpattern("cccnnn"));
      push(@{$data}, "Большой текст документа\n" x 20);
      $doc->{type} = "SIGN_REQUEST";
      $doc->{site} = 'test';
      $doc->{dec_data} = js::to_json($data);
      $doc->{template} = join("\n", @{$tmpl});

      $doc->{doc_id} = generate_doc_id();

      $dbh->do('INSERT INTO documents (id, code, doc_data, doc_template) VALUES (?, ?, ?, ?)', undef, $doc->{doc_id}, $code, $doc->{dec_data}, $doc->{template});
      my $dberr = $dbh->errstr;
      $dbh->commit;

      if (defined($dberr) && ($dberr ne '')) {
        print "Ошибка БД при создании нового документа<br>";
        warn $dberr;
      } else {
        send_sign_request($code, $doc);
      };

      print <<HTML
Документ для подписания отправлен. Проверьте новые документы в мобильно приложении<br>
<br>
<a href="/docs_list?code=$code">Проверка списка документов</a><br>
HTML
    }
    case '/docs_list' {
      my $code = $query->param('code');

      get_all_docs();

      print "<table border=\"1\" style=\"border: 4px double black; border-collapse: collapse; padding: 8px; margin: 8px; font-family:monospace;\" ><tr align=\"center\"><td width=\"10%\">Статус</td><td width=\"5%\">ID</td><td width=\"45%\">Данные</td><td width=\"30%\">Шаблон</td><td width=\"10%\">Подпись</td></tr>";
      
      my $c = $dbh->prepare('SELECT * FROM documents WHERE code = ?');
      $c->execute($code);
      while (my $doc = $c->fetchrow_hashref()) {
        print "<tr>";

        if (defined($doc->{doc_sign}) && ($doc->{doc_sign} ne '')) {
          print "<td align=\"center\"><b>ПОДПИСАН</b></td>";
        } else {
          print "<td align=\"center\"><b>Ожидает подписания</b></td>";
        };

        $doc->{doc_template} =~ s/\n/\<br\>/g;
        $doc->{doc_sign} = split_base64($doc->{doc_sign});
        $doc->{doc_sign} =~ s/\n/\<br\>/g;
        
        print "<td align=\"center\">".$doc->{id}."</td>";
        print "<td>".$doc->{doc_data}."</td>";
        print "<td>".$doc->{doc_template}."</td>";
        print "<td style=\"font-size: 6px;\">".$doc->{doc_sign}."</td>";
        
        print "</tr>";
      };
      $c->finish;

      print "</table><br>";
      print <<HTML;
      <br>
      <a href="/sign_request?code=$code">Генерация случайного документа на подписание</a><br>
      <a href="/sign_big_request?code=$code">Генерация БОЛЬШОГО документа на подписание</a><br>
      <a href="/sign_bad_template_request?code=$code">Генерация документа на подписание с неполным шаблоном</a><br>
HTML
    }
    else {
      print "ОШИБКА! Неизвестный запрос";
    };
  };

  print <<HTMLEND;
</body>
</html>
HTMLEND

  ########################################

	$pm->pm_post_dispatch();
};
closelog();

sub to_syslog {
	my ($msg) = @_;

	syslog("alert", $msg);
};

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

  send_doc($doc, '12345678');
};

sub get_all_docs {
  get_docs('12345678', \&get_one_doc);
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
        if (user_sign_is_valid($doc->{public_key}, $doc->{sign}, $doc->{code})) {
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

      if (!defined($sign) || ($sign eq '')) {
        my $c = $dbh->prepare('SELECT public_key FROM registrations WHERE code = ?');
        $c->execute($code);
        my ($pub_key) = $c->fetchrow_array;
        $c->finish;

        if (user_sign_is_valid($pub_key, $doc->{sign}, $doc->{site}.":".$doc->{doc_id}.":".$doc_data.":".$doc_template)) {
          $dbh->do('UPDATE documents SET doc_sign = ?, signed = ? WHERE id = ?', undef, $doc->{sign}, 1, $doc->{doc_id});
          $dbh->commit;
        } else {
          warn "Bad SIGN for document ".$doc->{doc_id};
        };
      };
    };
  };
};
