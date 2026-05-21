<?php
require_once(INCLUDE_DIR . 'class.plugin.php');

class BonescreenThemePlugin extends Plugin {
    function bootstrap() {
        global $ost;
        if (!$ost) {
            return;
        }

        $cssPath = __DIR__ . '/assets/modern.css';
        if (!is_readable($cssPath)) {
            return;
        }

        $css = file_get_contents($cssPath);
        if ($css === false || trim($css) === '') {
            return;
        }

        $ost->addExtraHeader("<style id=\"bonescreen-modern-theme\">\n" . $css . "\n</style>");
    }
}
