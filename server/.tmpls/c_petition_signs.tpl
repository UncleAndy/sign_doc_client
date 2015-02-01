<div id="masthead_nh">
  <p>&nbsp;</p>
  <h2>Петиция - подписи</h2>
  <p>&nbsp;</p>
  <p>Этот список демонстрирует в каком виде могут быть представлены подписи петиции.</p>
  <p>&nbsp;</p>

  <table id="signs_list">
    <tr>
      <th>
        Время подписания
      </td>
      <th>
        Идентификатор ключа
      </td>
      <th>
        Подпись
      </td>
    </tr>
    <? FOREACH sign IN list ?>
      <tr>
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
        <td align="center">
          <a href="/petition_sample" class="green-button-plain">&lt;&lt; Назад</a>
        </td>
      </tr>
    </table>
  </div>
</div>
