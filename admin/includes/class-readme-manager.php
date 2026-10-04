<?php
/**
 * WP Plugin Starter Read Me tab.
 *
 * Renders README.md with a small, escaping Markdown subset
 * (headings with GitHub-style IDs, lists, tables, bold, italic, inline code,
 * http(s) links, links to headings and images from the plugin's folder).
 * HTML comments and the GitHub badges block are left out.
 *
 * @package WPStarter
 * @since 0.2.0
 */

if (!defined('ABSPATH')) {
    exit;
}

class WPStarter_Readme_Manager {

    /**
     * Render the tab.
     */
    public static function display_tab_content() {
        $readme = wpstarter_get_readme_content();
        ?>
        <article class="wps-card wps-readme">
            <?php echo self::parse_markdown($readme['content']); // phpcs:ignore WordPress.Security.EscapeOutput -- built from escaped text. ?>
        </article>
        <?php
    }

    /**
     * Convert Markdown to HTML. Input is escaped first; only the generated
     * tags and validated http(s) links are emitted.
     *
     * @param string $markdown Markdown.
     * @return string HTML.
     */
    public static function parse_markdown($markdown) {
        $markdown = str_replace('{WPSTARTER_VERSION}', WPSTARTER_VERSION, $markdown);
        $markdown = str_replace(array("\r\n", "\r"), "\n", $markdown);
        // GitHub-only parts: the badges block (remote images) and HTML comments.
        $markdown = (string) preg_replace('/^<!-- aidevops:badges:start -->$.*?^<!-- aidevops:badges:end -->$/ms', '', $markdown);
        $markdown = (string) preg_replace('/^[ \t]*<!--(?:(?!-->).)*-->[ \t]*$/ms', '', $markdown);

        // The open list ('ul' or 'ol'), table ('head' after the header row,
        // then 'body') and the heading IDs used so far.
        $state = array('list' => '', 'table' => '', 'ids' => array());
        $html  = '';
        foreach (preg_split('/\r\n|\r|\n/', $markdown) ?: array() as $line) {
            $html .= self::block(trim($line), $state);
        }

        return $html . self::close_blocks($state);
    }

    /**
     * HTML for one trimmed line.
     *
     * @param string $trim  Line without surrounding whitespace.
     * @param array  $state Open list and table, heading IDs (updated).
     * @return string HTML.
     */
    private static function block($trim, array &$state) {
        if ('' === $trim || '#' === $trim) {
            return self::close_blocks($state);
        }
        if (self::is_table_line($trim)) {
            return self::table_row($trim, $state);
        }
        // A "- " or "* " item, or a "1. " item ($m[1] empty).
        if (preg_match('/^(?:([-*])|\d+\.)\s+(.+)$/', $trim, $m)) {
            return self::list_item('' === $m[1] ? 'ol' : 'ul', $m[2], $state);
        }
        return self::close_blocks($state) . self::single_block($trim, $state['ids']);
    }

    /**
     * HTML for a line that stands alone: an image, a heading or a paragraph.
     *
     * @param string $trim Line without surrounding whitespace.
     * @param array  $ids  Heading IDs used so far (updated).
     * @return string HTML.
     */
    private static function single_block($trim, array &$ids) {
        // An image on a line of its own, from the plugin's own folder.
        if (preg_match('/^!\[([^\]]*)\]\(([^)\s]+)\)$/', $trim, $m)) {
            return self::image($m[2], $m[1]);
        }
        if (preg_match('/^(#{1,4})\s+(.+)$/', $trim, $m)) {
            $level = min(4, strlen($m[1]) + 1); // h1 is reserved for the page title.
            return sprintf('<h%1$d id="%2$s">%3$s</h%1$d>', $level, esc_attr(self::anchor($m[2], $ids)), self::inline($m[2]));
        }
        return '<p>' . self::inline($trim) . '</p>';
    }

    /**
     * Close the open list or table.
     *
     * @param array $state Open list and table (updated).
     * @return string HTML.
     */
    private static function close_blocks(array &$state) {
        $html = '';
        if ($state['list']) {
            $html         .= '</' . $state['list'] . '>';
            $state['list'] = '';
        }
        if ($state['table']) {
            $html          .= ('head' === $state['table'] ? '</thead>' : '</tbody>') . '</table></div>';
            $state['table'] = '';
        }
        return $html;
    }

    /**
     * Whether a line is a table line: it starts and ends with |.
     *
     * @param string $trim Line without surrounding whitespace.
     * @return bool
     */
    private static function is_table_line($trim) {
        return strlen($trim) > 1 && '|' === $trim[0] && '|' === substr($trim, -1);
    }

    /**
     * A table line: a header row, a |---| separator, then body rows.
     *
     * @param string $trim  Line starting and ending with |.
     * @param array  $state Open list and table (updated).
     * @return string HTML.
     */
    private static function table_row($trim, array &$state) {
        if ('head' === $state['table'] && preg_match('/^\|[\s:|-]+\|$/', $trim)) {
            $state['table'] = 'body';
            return '</thead><tbody>';
        }
        $html = '';
        if (!$state['table']) {
            $html           = self::close_blocks($state) . '<div class="wps-readme-table"><table><thead>';
            $state['table'] = 'head';
        }
        $tag   = 'head' === $state['table'] ? 'th' : 'td';
        $html .= '<tr>';
        foreach (explode('|', substr($trim, 1, -1)) as $cell) {
            $html .= '<' . $tag . '>' . self::inline(trim($cell)) . '</' . $tag . '>';
        }
        return $html . '</tr>';
    }

    /**
     * A list item, opening its list (and closing another) when needed.
     *
     * @param string $type  'ul' or 'ol'.
     * @param string $text  Item Markdown.
     * @param array  $state Open list and table (updated).
     * @return string HTML.
     */
    private static function list_item($type, $text, array &$state) {
        $html = '';
        if ($state['list'] !== $type) {
            $html          = self::close_blocks($state) . '<' . $type . '>';
            $state['list'] = $type;
        }
        return $html . '<li>' . self::inline($text) . '</li>';
    }

    /**
     * Heading ID as GitHub makes it, so README links such as
     * `[Credits](#credits)` work in the tab too. Repeats get -1, -2...
     *
     * @param string $text Heading Markdown.
     * @param array  $ids  IDs used so far (updated).
     * @return string ID.
     */
    private static function anchor($text, array &$ids) {
        $text = preg_replace('/\[([^\]]+)\]\([^)]*\)/', '$1', $text);
        $text = str_replace(array('`', '*'), '', $text);
        $id   = function_exists('mb_strtolower') ? mb_strtolower($text, 'UTF-8') : strtolower($text);
        $id   = preg_replace('/[^\p{L}\p{N}\s_-]/u', '', $id);
        $id   = preg_replace('/\s/u', '-', trim($id));
        $base = '' === $id ? 'section' : $id;
        $id   = $base;
        $n    = 0;
        while (isset($ids[$id])) {
            $id = $base . '-' . (++$n);
        }
        $ids[$id] = true;

        return $id;
    }

    /**
     * An image from the plugin's folder, such as the banner at the top of
     * README.md. Only relative paths to image files that exist are shown, so
     * the tab never loads anything from another site.
     *
     * @param string $path Path relative to the plugin folder.
     * @param string $alt  Alternative text.
     * @return string HTML, or '' for anything else.
     */
    private static function image($path, $alt) {
        if (!preg_match('#^[a-z0-9_-]+(?:/[a-z0-9_-]+)*\.(?:svg|png|jpe?g|gif|webp)$#i', $path)) {
            return '';
        }
        $file = WPSTARTER_DIR . $path;
        if (!is_file($file)) {
            return '';
        }

        // Width and height stop the page jumping while the image loads.
        $size = '';
        if ('svg' === strtolower(pathinfo($path, PATHINFO_EXTENSION))) {
            $head = (string) file_get_contents($file, false, null, 0, 2048); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_get_contents_file_get_contents -- local file.
            if (preg_match('/<svg\b[^>]*?\swidth="(\d+)"[^>]*?\sheight="(\d+)"/', $head, $m)) {
                $size = array((int) $m[1], (int) $m[2]);
            }
        } else {
            $size = wp_getimagesize($file);
        }
        $dims = is_array($size) && !empty($size[0]) && !empty($size[1])
            ? sprintf(' width="%d" height="%d"', $size[0], $size[1])
            : '';

        // The file's time in the address, so browsers fetch a changed image
        // (such as a new banner after an update) instead of a cached one.
        $url = add_query_arg('ver', (string) filemtime($file), WPSTARTER_URL . $path);

        return sprintf(
            '<p class="wps-readme-image"><img src="%1$s" alt="%2$s"%3$s decoding="async" /></p>',
            esc_url($url),
            esc_attr($alt),
            $dims
        );
    }

    /**
     * Inline Markdown on escaped text.
     *
     * @param string $text Raw text.
     * @return string HTML.
     */
    private static function inline($text) {
        $text = esc_html($text);
        $text = preg_replace('/`([^`]+)`/', '<code>$1</code>', $text);
        $text = preg_replace('/\*\*(.+?)\*\*/', '<strong>$1</strong>', $text);
        $text = preg_replace('/(?<![*\w])\*(?!\s)(.+?)(?<!\s)\*(?![*\w])/', '<em>$1</em>', $text);

        return preg_replace_callback('/\[([^\]]+)\]\(([^)\s]+)\)/', function ($m) {
            $url = esc_url(html_entity_decode($m[2]), array('http', 'https'));
            if ('#' === $m[2][0]) {
                return sprintf('<a href="#%1$s">%2$s</a>', esc_attr(substr($m[2], 1)), $m[1]);
            }
            if ('' === $url) {
                return $m[1];
            }
            return sprintf('<a href="%1$s" target="_blank" rel="noopener noreferrer">%2$s</a>', $url, $m[1]);
        }, $text);
    }
}
