<?php

declare(strict_types=1);

$target = '/var/www/html/src/plugins/orangehrmOpenidAuthenticationPlugin/Service/SocialMediaAuthenticationService.php';
$endpointMarker = "'authorization_endpoint'";
$redirectMarker = "ORANGEHRM_PUBLIC_URL";


$publicBaseUri = getenv('ORANGEHRM_OIDC_PUBLIC_BASE_URI');
if (is_string($publicBaseUri) && $publicBaseUri !== '') {
    $databaseHost = getenv('ORANGEHRM_DATABASE_HOST');
    $databasePort = getenv('ORANGEHRM_DATABASE_PORT') ?: '3306';
    $databaseName = getenv('ORANGEHRM_DATABASE_NAME');
    $databaseUser = getenv('ORANGEHRM_DATABASE_USER');
    $databasePassword = getenv('ORANGEHRM_DATABASE_PASSWORD');

    $pdo = new PDO(
        "mysql:host={$databaseHost};port={$databasePort};dbname={$databaseName};charset=utf8mb4",
        $databaseUser,
        $databasePassword,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION],
    );
    try {
        $statement = $pdo->prepare(
            'UPDATE ohrm_openid_provider SET provider_url = :provider_url WHERE provider_name = :provider_name'
        );
        $statement->execute([
            'provider_url' => rtrim($publicBaseUri, '/'),
            'provider_name' => 'Keycloak',
        ]);
        fwrite(STDOUT, "OrangeHRM public OIDC provider URL is configured.\n");
    } catch (PDOException $exception) {
        if ($exception->getCode() !== '42S02') {
            throw $exception;
        }
        fwrite(STDOUT, "OrangeHRM OIDC provider table is not initialized yet; public URL update skipped.\n");
    }
}

if (!is_file($target)) {
    fwrite(STDERR, "OrangeHRM OIDC service file not found: {$target}\n");
    exit(1);
}

$source = file_get_contents($target);
if ($source === false) {
    fwrite(STDERR, "Unable to read OrangeHRM OIDC service file: {$target}\n");
    exit(1);
}

$replacement = <<<'PHP'
        // Keep browser authorization public, but use Docker networking for server-side OIDC calls.
        $providerConfig = [];
        $publicBaseUri = getenv('ORANGEHRM_OIDC_PUBLIC_BASE_URI');
        if (is_string($publicBaseUri) && $publicBaseUri !== '') {
            $publicBaseUri = rtrim($publicBaseUri, '/');
            $providerConfig['authorization_endpoint'] = $publicBaseUri . '/protocol/openid-connect/auth';
        }

        $internalBaseUri = getenv('ORANGEHRM_OIDC_INTERNAL_BASE_URI');
        if (is_string($internalBaseUri) && $internalBaseUri !== '') {
            $internalBaseUri = rtrim($internalBaseUri, '/');
            $providerConfig['token_endpoint'] = $internalBaseUri . '/protocol/openid-connect/token';
            $providerConfig['userinfo_endpoint'] = $internalBaseUri . '/protocol/openid-connect/userinfo';
            $providerConfig['jwks_uri'] = $internalBaseUri . '/protocol/openid-connect/certs';
        }

        if ($providerConfig !== []) {
            $oidcClient->providerConfigParam($providerConfig);
        }

        $oidcClient->addScope([$scope]);
PHP;

$legacyPatch = <<<'PHP'
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

$patched = $source;
if (!str_contains($patched, $endpointMarker)) {
    $needle = str_contains($patched, 'ORANGEHRM_OIDC_INTERNAL_BASE_URI')
        ? $legacyPatch
        : <<<'PHP'
        $oidcClient->addScope([$scope]);
PHP;

    if (substr_count($patched, $needle) !== 1) {
        fwrite(STDERR, "OrangeHRM OIDC endpoint patch anchor was not found exactly once; refusing to modify the file.\n");
        exit(1);
    }
    $patched = str_replace($needle, $replacement, $patched);
}

if (!str_contains($patched, $redirectMarker)) {
    $redirectNeedle = <<<'PHP'
        /** @var UrlGenerator $urlGenerator */
        $urlGenerator = $this->getContainer()->get(Services::URL_GENERATOR);
        return $urlGenerator->generate('auth_oidc_login_redirect', [], UrlGenerator::ABSOLUTE_URL);
PHP;
    $redirectReplacement = <<<'PHP'
        $publicUrl = getenv('ORANGEHRM_PUBLIC_URL');
        if (is_string($publicUrl) && $publicUrl !== '') {
            return rtrim($publicUrl, '/') . '/web/index.php/openidauth/openIdCredentials';
        }

        /** @var UrlGenerator $urlGenerator */
        $urlGenerator = $this->getContainer()->get(Services::URL_GENERATOR);
        return $urlGenerator->generate('auth_oidc_login_redirect', [], UrlGenerator::ABSOLUTE_URL);
PHP;
    if (substr_count($patched, $redirectNeedle) !== 1) {
        fwrite(STDERR, "OrangeHRM public redirect patch anchor was not found exactly once; refusing to modify the file.\n");
        exit(1);
    }
    $patched = str_replace($redirectNeedle, $redirectReplacement, $patched);
}

if ($patched === $source) {
    fwrite(STDOUT, "OrangeHRM OIDC endpoints are already configured.\n");
    exit(0);
}
if (file_put_contents($target, $patched) === false) {
    fwrite(STDERR, "Unable to write OrangeHRM OIDC service file: {$target}\n");
    exit(1);
}

fwrite(STDOUT, "Configured OrangeHRM public and internal OIDC endpoints.\n");
