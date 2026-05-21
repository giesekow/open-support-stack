<?php
$supportHost = getenv('SUPPORT_HOST') ?: '';
$pluginUrl = $supportHost ? ('https://' . $supportHost) : 'https://support.example.com';

return array(
    'id' =>             'bonescreen:theme',
    'version' =>        '0.1.0',
    'name' =>           'Bonescreen Modern Theme',
    'author' =>         'Bonescreen',
    'description' =>    'Applies a modernized UI theme for osTicket portal and agent panel.',
    'url' =>            $pluginUrl,
    'plugin' =>         'bonescreen_theme.php:BonescreenThemePlugin',
);
?>
