<?php
/**
 * Composer lock file integrity tests.
 *
 * @package WPALLSTARS\PluginStarterTemplate
 */

/**
 * Composer lock file integrity test case.
 */
class Composer_Lock_Test extends \PHPUnit\Framework\TestCase {

    /**
     * Test that the PHPUnit polyfills lock metadata matches the installed package.
     *
     * @return void
     */
    public function test_phpunit_polyfills_lock_metadata_matches_installed_package() {
        $root_dir      = dirname( dirname( __DIR__ ) );
        $lock_data     = $this->read_json_file( $root_dir . '/composer.lock' );
        $package_data  = $this->read_json_file( $root_dir . '/vendor/yoast/phpunit-polyfills/composer.json' );
        $lock_packages = array_merge( $lock_data['packages'] ?? array(), $lock_data['packages-dev'] ?? array() );
        $lock_package  = null;

        foreach ( $lock_packages as $package ) {
            if ( 'yoast/phpunit-polyfills' === ( $package['name'] ?? '' ) ) {
                $lock_package = $package;
                break;
            }
        }

        $this->assertIsArray( $lock_package, 'yoast/phpunit-polyfills must be present in composer.lock.' );
        $this->assertSame( $package_data['require'], $lock_package['require'] );
        $this->assertSame( $package_data['require-dev'], $lock_package['require-dev'] );
        $this->assertSame( $package_data['extra'], $lock_package['extra'] );

        foreach ( $package_data['support'] as $support_type => $support_url ) {
            $this->assertSame( $support_url, $lock_package['support'][ $support_type ] );
        }
    }

    /**
     * Read and decode a JSON file.
     *
     * @param string $file_path JSON file path.
     * @return array<string, mixed>
     */
    private function read_json_file( $file_path ) {
        $this->assertFileExists( $file_path );

        $contents = file_get_contents( $file_path );
        $this->assertIsString( $contents );

        $data = json_decode( $contents, true );
        $this->assertIsArray( $data );

        return $data;
    }
}
