<?php
/**
 * Count the plugins WP Plugin Starter replaces and keep README.md's count right.
 *
 * Reads every 'replaces' entry in includes/ (the same lists the Plugins screen
 * uses), without loading WordPress: array literals, class constants
 * (self::X, Class::X), variables assigned in the same file and + unions.
 * Anything else stops the script, so it never counts wrong in silence.
 *
 * Usage: php scripts/replaced-plugins.php [--check | --write] [DIR]
 *   (none)    List the replaced plugins (slug and name) and the count.
 *   --check   Exit 1 when README.md's "WP Plugin Starter replaces **N plugins**"
 *             line has another count. Offline; scripts/preflight-release.sh
 *             runs it on the release build.
 *   --write   Rewrite that line with the count and download sizes: each
 *             plugin's zip from WordPress.org (or its GitHub release, see
 *             GITHUB_SOURCES) against WP Plugin Starter's GitHub release zip,
 *             built from HEAD with scripts/build-release.sh. Needs network.
 *   DIR       Plugin folder to read (default: this checkout).
 *
 * Exit status: 0 when fine, 1 when --check finds a different count, 2 on errors.
 */

// Replaced plugins that are not on WordPress.org but have GitHub releases.
const GITHUB_SOURCES = array('git-updater' => 'afragen/git-updater');
// The name is quoted for the pattern: a renamed plugin's may hold ( . + etc.
define('README_LINE', '/^' . preg_quote('WP Plugin Starter', '/') . ' replaces \*\*(\d+) plugins\*\*.*$/m');

/**
 * Stop with a message.
 *
 * @param string $message What went wrong.
 */
function fail($message) {
    fwrite(STDERR, "replaced-plugins: $message\n");
    exit(2);
}

/**
 * Tokens of a PHP file without whitespace and comments, as [id, text, line].
 *
 * @param string $file Path.
 * @return array
 */
function tokens($file) {
    $out  = array();
    $line = 1;
    foreach (token_get_all(file_get_contents($file)) as $token) {
        if (is_array($token)) {
            $line = $token[2];
            if (in_array($token[0], array(T_WHITESPACE, T_COMMENT, T_DOC_COMMENT), true)) {
                continue;
            }
            $out[] = array($token[0], $token[1], $line);
        } else {
            $out[] = array($token, $token, $line);
        }
    }
    return $out;
}

/**
 * Small evaluator for the expressions used in 'replaces'.
 */
final class Replaces_Reader {
    /** @var array "Class::NAME" => array(file, tokens, start, class). */
    private $consts = array();
    /** @var array Slug => name. */
    public $plugins = array();
    /** @var array Slug => list of "file:line". */
    public $where = array();

    /** @var array Current file's tokens. */
    private $t;
    /** @var int Current position. */
    private $i;
    /** @var string Current file. */
    private $file;
    /** @var string Current class. */
    private $class;
    /** @var array Variable name => position of its value in $t. */
    private $vars;

    /**
     * Read every PHP file under $dir/includes.
     *
     * @param string $dir Plugin folder.
     */
    public function read($dir) {
        $files = array();
        $it    = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir . '/includes', FilesystemIterator::SKIP_DOTS));
        foreach ($it as $f) {
            if ('php' === $f->getExtension()) {
                $files[] = $f->getPathname();
            }
        }
        sort($files);
        $parsed = array();
        foreach ($files as $file) {
            $parsed[$file] = tokens($file);
            $this->collect_consts($file, $parsed[$file]);
        }
        foreach ($parsed as $file => $t) {
            $this->collect_replaces($file, $t, $dir);
        }
        ksort($this->plugins);
    }

    private function collect_consts($file, array $t) {
        $class = '';
        foreach ($t as $i => $tok) {
            if (T_CLASS === $tok[0] && isset($t[$i + 1]) && T_STRING === $t[$i + 1][0]) {
                $class = $t[$i + 1][1];
            }
            if (T_CONST === $tok[0] && '' !== $class && isset($t[$i + 2]) && '=' === $t[$i + 2][0]) {
                $this->consts[$class . '::' . $t[$i + 1][1]] = array($file, $t, $i + 3, $class);
            }
        }
    }

    private function collect_replaces($file, array $t, $dir) {
        $this->file  = $file;
        $this->t     = $t;
        $this->class = '';
        $this->vars  = array();
        $n           = count($t);
        for ($i = 0; $i < $n; $i++) {
            $tok = $t[$i];
            if (T_CLASS === $tok[0] && isset($t[$i + 1]) && T_STRING === $t[$i + 1][0]) {
                $this->class = $t[$i + 1][1];
            } elseif (T_VARIABLE === $tok[0] && isset($t[$i + 1]) && '=' === $t[$i + 1][0]) {
                $this->vars[$tok[1]] = $i + 2;
            } elseif (T_CONSTANT_ENCAPSED_STRING === $tok[0] && "'replaces'" === $tok[1] && isset($t[$i + 1]) && T_DOUBLE_ARROW === $t[$i + 1][0]) {
                $this->i = $i + 2;
                $value   = $this->expr();
                if (!is_array($value)) {
                    $this->error('replaces is not an array');
                }
                foreach ($value as $slug => $name) {
                    if (!is_string($name)) {
                        $this->error("replaces[$slug] is not a name");
                    }
                    if (!isset($this->plugins[$slug])) {
                        $this->plugins[$slug] = $name;
                    }
                    $this->where[$slug][] = substr($file, strlen($dir) + 1) . ':' . $tok[2];
                }
            }
        }
    }

    private function error($message) {
        $line = isset($this->t[$this->i]) ? $this->t[$this->i][2] : '?';
        fail("{$this->file}:$line: $message");
    }

    private function peek() {
        return isset($this->t[$this->i]) ? $this->t[$this->i] : array(null, '', 0);
    }

    private function expect($id) {
        $tok = $this->peek();
        if ($tok[0] !== $id) {
            $this->error("expected $id, found '{$tok[1]}'");
        }
        $this->i++;
    }

    /** expr := term ('+' term)* */
    private function expr() {
        $value = $this->term();
        while ('+' === $this->peek()[0]) {
            $this->i++;
            $right = $this->term();
            if (!is_array($value) || !is_array($right)) {
                $this->error('+ on something that is not an array');
            }
            $value = $value + $right;
        }
        return $value;
    }

    private function term() {
        $tok = $this->peek();
        if (T_ARRAY === $tok[0]) {
            $this->i++;
            $this->expect('(');
            return $this->elements(')');
        }
        if ('[' === $tok[0]) {
            $this->i++;
            return $this->elements(']');
        }
        if (T_CONSTANT_ENCAPSED_STRING === $tok[0]) {
            $this->i++;
            return $this->string($tok[1]);
        }
        if (T_STRING === $tok[0] && isset($this->t[$this->i + 1]) && T_DOUBLE_COLON === $this->t[$this->i + 1][0]) {
            $class   = in_array(strtolower($tok[1]), array('self', 'static'), true) ? $this->class : $tok[1];
            $name    = $this->t[$this->i + 2][1];
            $this->i += 3;
            return $this->constant($class . '::' . $name);
        }
        if (T_STATIC === $tok[0] && isset($this->t[$this->i + 1]) && T_DOUBLE_COLON === $this->t[$this->i + 1][0]) {
            $name    = $this->t[$this->i + 2][1];
            $this->i += 3;
            return $this->constant($this->class . '::' . $name);
        }
        if (T_VARIABLE === $tok[0]) {
            if (!isset($this->vars[$tok[1]])) {
                $this->error("{$tok[1]} is not assigned before it is used");
            }
            $back    = $this->i + 1;
            $this->i = $this->vars[$tok[1]];
            $value   = $this->expr();
            $this->i = $back;
            return $value;
        }
        $this->error("cannot read '{$tok[1]}'");
    }

    private function elements($close) {
        $out = array();
        while ($close !== $this->peek()[0]) {
            $key = $this->expr();
            $this->expect(T_DOUBLE_ARROW);
            $out[$key] = $this->expr();
            if (',' === $this->peek()[0]) {
                $this->i++;
            } elseif ($close !== $this->peek()[0]) {
                $this->error("expected , or $close");
            }
        }
        $this->i++;
        return $out;
    }

    private function string($text) {
        if ("'" !== $text[0]) {
            $this->error("only single-quoted strings are read: $text");
        }
        return strtr(substr($text, 1, -1), array("\\'" => "'", '\\\\' => '\\'));
    }

    private function constant($key) {
        if (!isset($this->consts[$key])) {
            $this->error("unknown constant $key");
        }
        list($file, $t, $start, $class) = $this->consts[$key];
        $saved = array($this->file, $this->t, $this->i, $this->class);
        list($this->file, $this->t, $this->i, $this->class) = array($file, $t, $start, $class);
        $value = $this->expr();
        list($this->file, $this->t, $this->i, $this->class) = $saved;
        return $value;
    }
}

/**
 * GET a URL; the body, or null on a network error.
 *
 * @param string $url URL.
 * @param bool   $head Only the headers (returns the Content-Length).
 * @return string|int|null
 */
function fetch($url, $head = false) {
    $args = array('-sSL', '-m', '30', '-A', 'wpstarter-replaced-plugins');
    if ($head) {
        $args = array_merge($args, array('-o', '/dev/null', '-w', '%{http_code} %{size_download}'));
    }
    $cmd = 'curl ' . implode(' ', array_map('escapeshellarg', $args)) . ' ' . escapeshellarg($url);
    exec($cmd, $lines, $status);
    if (0 !== $status) {
        return null;
    }
    $out = implode("\n", $lines);
    if ($head) {
        list($code, $bytes) = explode(' ', $out) + array('', '0');
        return '200' === $code ? (int) $bytes : null;
    }
    return $out;
}

/**
 * Size of a plugin's current zip: WordPress.org first, then GITHUB_SOURCES.
 *
 * @param string $slug Plugin folder.
 * @return int|null Bytes, or null when it cannot be downloaded.
 */
function zip_size($slug) {
    $info = fetch('https://api.wordpress.org/plugins/info/1.2/?action=plugin_information&request%5Bslug%5D=' . rawurlencode($slug) . '&request%5Bfields%5D%5Bsections%5D=0');
    if (null === $info) {
        fail("could not reach WordPress.org for $slug");
    }
    $data = json_decode($info, true);
    if (is_array($data) && !empty($data['download_link'])) {
        $bytes = fetch($data['download_link'], true);
        if (null === $bytes) {
            fail("could not download {$data['download_link']}");
        }
        return $bytes;
    }
    if (isset(GITHUB_SOURCES[$slug])) {
        $json = fetch('https://api.github.com/repos/' . GITHUB_SOURCES[$slug] . '/releases/latest');
        $data = null === $json ? null : json_decode($json, true);
        foreach (is_array($data) && isset($data['assets']) ? $data['assets'] : array() as $asset) {
            if (0 === strpos($asset['name'], $slug) && '.zip' === substr($asset['name'], -4)) {
                return (int) $asset['size'];
            }
        }
        fail('no release zip for ' . GITHUB_SOURCES[$slug]);
    }
    return null; // Pro editions and plugins closed on WordPress.org.
}

/**
 * Bytes as "1.2 MB" or "870 KB".
 *
 * @param int $bytes Bytes.
 * @return string
 */
function size_label($bytes) {
    if ($bytes >= 1024 * 1024) {
        return number_format($bytes / (1024 * 1024), 1) . ' MB';
    }
    return number_format($bytes / 1024) . ' KB';
}

$mode = '';
$dir  = dirname(__DIR__);
foreach (array_slice($argv, 1) as $arg) {
    if ('--check' === $arg || '--write' === $arg) {
        $mode = $arg;
    } elseif ('-h' === $arg || '--help' === $arg) {
        echo "Usage: php scripts/replaced-plugins.php [--check | --write] [DIR]\n";
        exit(0);
    } elseif ('-' !== $arg[0]) {
        $dir = rtrim($arg, '/');
    } else {
        fail("unknown argument: $arg");
    }
}
if (!is_dir($dir . '/includes')) {
    fail("$dir has no includes folder");
}

$reader = new Replaces_Reader();
$reader->read($dir);
$count = count($reader->plugins);

$readme_file = $dir . '/README.md';
$readme      = is_file($readme_file) ? file_get_contents($readme_file) : '';

if (0 === $count) {
    // A plugin that replaces none has no count line in README.md. With the
    // line there, finding none means the reader no longer understands the code.
    if (preg_match(README_LINE, $readme)) {
        fail('no replaced plugins found; the reader is out of date');
    }
    echo "No replaced plugins, and README.md has no count line\n";
    exit(0);
}

if ('' === $mode) {
    foreach ($reader->plugins as $slug => $name) {
        printf("%-42s %s\n", $slug, $name);
    }
    printf("%d plugins\n", $count);
    exit(0);
}

if ('--check' === $mode) {
    if (!preg_match(README_LINE, $readme, $m)) {
        fwrite(STDERR, "README.md has no \"WP Plugin Starter replaces **N plugins**\" line\n");
        exit(1);
    }
    if ((int) $m[1] !== $count) {
        fwrite(STDERR, "README.md says {$m[1]} replaced plugins, the code has $count; run php scripts/replaced-plugins.php --write\n");
        exit(1);
    }
    echo "README.md says $count replaced plugins, as the code does\n";
    exit(0);
}

// --write: sizes of every replaced plugin that can be downloaded, and ours.
$total     = 0;
$sized     = 0;
$no_size   = array();
foreach ($reader->plugins as $slug => $name) {
    $bytes = zip_size($slug);
    if (null === $bytes) {
        $no_size[] = $name;
        continue;
    }
    $total += $bytes;
    $sized++;
    printf("%-42s %10s\n", $slug, size_label($bytes));
}

$out = sys_get_temp_dir() . '/wpstarter-replaced-' . getmypid();
exec('cd ' . escapeshellarg($dir) . ' && scripts/build-release.sh --ref HEAD --out ' . escapeshellarg($out) . ' --quiet', $zips, $status);
if (0 !== $status || empty($zips[0]) || !is_file($zips[0])) {
    fail('scripts/build-release.sh failed');
}
$ours = filesize($zips[0]);
array_map('unlink', glob($out . '/*.zip'));
@rmdir($out);

$line = sprintf(
    'WP Plugin Starter replaces **%d plugins**, some of them in part, with free and Pro editions counted separately. The %d that can be downloaded come to %s zipped; WP Plugin Starter is %s.',
    $count,
    $sized,
    size_label($total),
    size_label($ours)
);
printf("%d plugins; %d downloadable, %s; WP Plugin Starter %s\n", $count, $sized, size_label($total), size_label($ours));
if ($no_size) {
    echo 'Not downloadable (Pro or closed): ' . implode(', ', $no_size) . "\n";
}
if (!preg_match(README_LINE, $readme)) {
    fail('README.md has no "WP Plugin Starter replaces **N plugins**" line to update; add one above the Features table');
}
file_put_contents($readme_file, preg_replace(README_LINE, str_replace(array('\\', '$'), array('\\\\', '\\$'), $line), $readme, 1));
echo "Updated README.md\n";
