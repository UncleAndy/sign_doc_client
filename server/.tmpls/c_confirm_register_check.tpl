<div id="masthead_nh">
  <p>&nbsp;</p>
  <h2>Подтверждение действия - проверка регистрации</h2>
  <p>&nbsp;</p>
  <p>На это странице вам выдается результат регистрации вашей подписи по одноразовому коду.</p>
  <p>&nbsp;</p>
  <? IF is_register ?>
    <p><b>Ваша электронная подпись зарегистрирована</b></p>
  <? ELSE ?>
    <p><b>Пока ваша подпись не зарегистрирована</b></p>
  <? END ?>
  <p>&nbsp;</p>
</div>
<div id="blue-bar">
	&nbsp;
</div>
<div id="main">
  <div id="content">
    <table width="100%">
      <tr>
        <td align="left">
          <a href="/confirm_sample/register?code=<? code ?>" class="green-button-plain">&lt;&lt; Назад</a>
        </td>
        <td align="right">
          <a href="/confirm_sample/action?code=<? code ?>" class="green-button-plain">Подтверждение &gt;&gt;</a>
        </td>
      </tr>
    </table>
  </div>
</div>
