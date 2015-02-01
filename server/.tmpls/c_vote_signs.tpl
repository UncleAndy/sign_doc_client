<div id="masthead_nh">
  <p>&nbsp;</p>
  <h2>Голосование - результаты</h2>
  <p>&nbsp;</p>
  <p>Здесь приведен общий результат голосования и список подписанных голосов, из которых он складывается.</p>
  <p>&nbsp;</p>
  <h3>Сводные результаты</h3>
  <table id="signs_list">
    <tr>
      <td>Вариант 1</td>
      <td><? choise1_count ?></td>
    </tr>
    <tr>
      <td>Вариант 2</td>
      <td><? choise2_count ?></td>
    </tr>
    <tr>
      <td>Вариант 3</td>
      <td><? choise3_count ?></td>
    </tr>
  </table>
  <p>&nbsp;</p>
  <h3>Список голосов</h3>
  <table id="signs_list">
    <tr>
      <th>Выбор</th>
      <th>Время подписания</th>
      <th>Идентификатор ключа</th>
      <th>Представление</th>
    </tr>
    <? FOREACH sign IN list ?>
      <tr>
        <td>
          <? sign.choise ?>
        </td>
        <td>
          <? sign.t_sign ?>
        </td>
        <td>
          <? sign.user_key_id ?>
        </td>
        <td>
          <? sign.person_info ?>
        </td>
      </tr>
    <? END ?>
  </table>
  <p>&nbsp;</p>
</div>
<div id="blue-bar">
	&nbsp;
</div>
<div id="main">
  <div id="content">
    <table width="100%">
      <tr>
        <td align="left" width="33%">
          &nbsp;
        </td>
        <td align="center" width="33%">
          <a href="/vote_sample" class="green-button-plain">&lt;&lt; Назад</a>
        </td>
        <td align="right" width="33%">
          &nbsp;
        </td>
      </tr>
    </table>
  </div>
</div>
