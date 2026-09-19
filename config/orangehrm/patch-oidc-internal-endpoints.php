<?php

declare(strict_types=1);

$target = '/var/www/html/src/plugins/orangehrmOpenidAuthenticationPlugin/Service/SocialMediaAuthenticationService.php';
$marker = 'ORANGEHRM_OIDC_INTERNAL_BASE_URI';

if (!is_file($target)) {
    fwrite(STDERR, "OrangeHRM OIDC service file not found: {$target}\n");
    exit(1);
}

$source = file_get_contents($target);
if ($source === false) {
    fwrite(STDERR, "Unable to read OrangeHRM OIDC service file: {$target}\n");
    exit(1);
}

if (str_contains($source, $marker)) {
    fwrite(STDOUT, "OrangeHRM internal OIDC endpoints are already configured.\n");
    exit(0);
}

$needle = <<<'PHP'
        $oidcClient->addScope([$scope]);
PHP;

$replacement = <<<'PHP'
        // Keep browser authorization public, but use Docker networking for server-side OIDC calls.
        $internalBaseUri = getenv('ORANGEHRM_OIDC_INTERNAL_BASE_URI');
        if (is_string($internalBaseUri) && $internalBaseUri !== '') {
            $internalBaseUri = rtrim($internalBaseUri, '/');
            $oidcClient->providerConfigParam([
                'token_endpoint' => $internalBaseUri . '/protocol/openid-connect/token',
                'userinfo_endpoint' => $internalBaseUri . '/protocol/openid-connect/userinfo',
                'jwks_uri' => $internalBaseUri . '/protocol/openid-connect/certs',
            ]);
        }

        $oidcClient->addScope([$scope]);
PHP;

if (substr_count($source, $needle) !== 1) {
    fwrite(STDERR, "OrangeHRM OIDC patch anchor was not found exactly once; refusing to modify the file.\n");
    exit(1);
}

$patched = str_replace($needle, $replacement, $source);
if (file_put_contents($target, $patched) === false) {
    fwrite(STDERR, "Unable to write OrangeHRM OIDC service file: {$target}\n");
    exit(1);
}

fwrite(STDOUT, "Configured OrangeHRM internal OIDC endpoints.\n");
