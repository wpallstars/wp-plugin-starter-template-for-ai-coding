<?php
/**
 * WP Plugin Starter settings tabs.
 *
 * Renders setting cards from WPStarter_Settings::schema(). Each top-level
 * setting is a card with a switch; child settings appear in an expandable
 * panel. Controls save instantly via AJAX (see admin/js/wpstarter-admin.js).
 *
 * @package WPStarter
 * @since 0.2.0
 */

if (!defined('ABSPATH')) {
    exit;
}

class WPStarter_Settings_Manager {

    /**
     * Render matching settings from every tab, grouped by tab.
     *
     * Cards are the same as on their own tab, so they can be switched on
     * and changed here.
     *
     * @param string $query Search text.
     * @param array  $tabs  Registered tabs (see WPStarter_Admin_Manager::get_tabs()).
     */
    public static function render_search($query, array $tabs) {
        $groups = array();
        foreach (WPStarter_Settings::search($query) as $key => $field) {
            if (isset($tabs[$field['tab']])) {
                $groups[$field['tab']][$key] = $field;
            }
        }
        $count = array_sum(array_map('count', $groups));
        ?>
        <div class="wps-section">
            <div class="wps-section__intro">
                <h2 class="wps-section__title">
                    <?php
                    /* translators: %s: search text */
                    echo esc_html(sprintf(__('Results for “%s”', 'wp-plugin-starter-template'), $query));
                    ?>
                </h2>
                <p class="wps-section__desc" role="status">
                    <?php
                    echo esc_html($count
                        /* translators: %d: number of matching features */
                        ? sprintf(_n('%d feature found.', '%d features found.', $count, 'wp-plugin-starter-template'), $count)
                        : __('No features match. Try another word.', 'wp-plugin-starter-template'));
                    ?>
                </p>
                <?php if ($count) : ?>
                    <p class="wps-section__hint"><?php esc_html_e('Changes are saved automatically.', 'wp-plugin-starter-template'); ?></p>
                <?php endif; ?>
            </div>
            <?php foreach ($groups as $tab => $fields) : ?>
                <h3 class="wps-search__group">
                    <a href="<?php echo esc_url(WPStarter_Admin_Manager::tab_url($tab)); ?>"><?php echo esc_html($tabs[$tab]['label']); ?></a>
                </h3>
                <div class="wps-cards">
                    <?php
                    foreach ($fields as $key => $field) {
                        self::render_card($key, $field);
                    }
                    ?>
                </div>
            <?php endforeach; ?>
        </div>
        <?php
    }

    /**
     * Render every top-level setting for a tab.
     *
     * @param string $tab         Tab slug.
     * @param string $title       Section heading.
     * @param string $description Section intro.
     */
    public static function render_tab($tab, $title, $description) {
        $fields = WPStarter_Settings::fields_for_tab($tab);
        ?>
        <div class="wps-section">
            <div class="wps-section__intro">
                <h2 class="wps-section__title"><?php echo esc_html($title); ?></h2>
                <?php if ($description) : ?>
                    <p class="wps-section__desc"><?php echo esc_html($description); ?></p>
                <?php endif; ?>
                <?php if ($fields) : ?>
                    <p class="wps-section__hint"><?php esc_html_e('Changes are saved automatically.', 'wp-plugin-starter-template'); ?></p>
                <?php endif; ?>
            </div>
            <?php if ($fields) : ?>
                <div class="wps-cards">
                    <?php
                    foreach ($fields as $key => $field) {
                        self::render_card($key, $field);
                    }
                    ?>
                </div>
            <?php else : ?>
                <div class="wps-card wps-empty">
                    <p><?php esc_html_e('No settings yet.', 'wp-plugin-starter-template'); ?></p>
                </div>
            <?php endif; ?>
            <?php
            /**
             * Fires after a settings tab's cards, for sections that are not
             * settings (such as example data).
             *
             * @param string $tab Tab slug.
             */
            do_action('wpstarter_settings_tab_after', $tab);
            ?>
        </div>
        <?php
    }

    /**
     * Render a setting card.
     *
     * @param string $key   Setting key.
     * @param array  $field Schema entry.
     */
    public static function render_card($key, array $field) {
        // Hidden options are wiring set by starter data or code, not choices.
        $children = array_filter(WPStarter_Settings::children_of($key), function ($child) {
            return empty($child['hidden']);
        });
        $value    = WPStarter_Settings::get($key);
        $id       = 'wps-' . $key;
        $panel_id = $id . '-panel';
        $is_bool  = 'bool' === $field['type'];
        ?>
        <section class="wps-card wps-setting<?php echo ($is_bool && $value) ? ' is-on' : ''; ?><?php echo $children ? ' has-panel' : ''; ?>" data-setting-card="<?php echo esc_attr($key); ?>">
            <?php // Clicking the header (outside the switch) opens the options; only the switch changes the value. ?>
            <div class="wps-setting__header"<?php echo $children ? ' data-wps-panel-toggle' : ''; ?>>
                <?php if ($is_bool) : ?>
                    <span class="wps-switch">
                        <input type="checkbox"
                               role="switch"
                               class="wps-switch__input"
                               id="<?php echo esc_attr($id); ?>"
                               data-wps-setting="<?php echo esc_attr($key); ?>"
                               aria-labelledby="<?php echo esc_attr($id); ?>-title"
                               aria-describedby="<?php echo esc_attr($id); ?>-desc"
                               <?php checked((bool) $value); ?> />
                        <span class="wps-switch__track" aria-hidden="true"></span>
                    </span>
                <?php endif; ?>

                <div class="wps-setting__text">
                    <div class="wps-setting__title-row">
                        <span class="wps-setting__title" id="<?php echo esc_attr($id); ?>-title"><?php echo esc_html($field['label']); ?></span>
                        <span class="wps-status" data-wps-status="<?php echo esc_attr($key); ?>" aria-hidden="true"></span>
                    </div>
                    <?php if (!empty($field['description'])) : ?>
                        <p class="wps-setting__desc" id="<?php echo esc_attr($id); ?>-desc"><?php echo esc_html($field['description']); ?></p>
                    <?php endif; ?>
                    <?php self::render_replaces($field); ?>
                </div>

                <?php if ($children) : ?>
                    <button type="button"
                            class="wps-setting__expand button-link"
                            aria-expanded="false"
                            aria-controls="<?php echo esc_attr($panel_id); ?>">
                        <span class="wps-setting__expand-label"><?php esc_html_e('Options', 'wp-plugin-starter-template'); ?></span>
                        <span class="dashicons dashicons-arrow-down-alt2" aria-hidden="true"></span>
                        <span class="screen-reader-text"><?php echo esc_html(sprintf(/* translators: %s: setting name */ __('for %s', 'wp-plugin-starter-template'), $field['label'])); ?></span>
                    </button>
                <?php endif; ?>
            </div>

            <?php if ($children) : ?>
                <div class="wps-setting__panel" id="<?php echo esc_attr($panel_id); ?>" hidden>
                    <?php
                    /**
                     * Fires at the top of a setting's options panel, for status
                     * such as progress (wrap output in .wps-panel-note).
                     *
                     * @param string $key   Setting key.
                     * @param array  $field Schema entry.
                     */
                    do_action('wpstarter_setting_panel', $key, $field);
                    foreach ($children as $child_key => $child) {
                        self::render_field($child_key, $child);
                    }
                    ?>
                </div>
            <?php endif; ?>
        </section>
        <?php
    }

    /**
     * Note which plugins a setting replaces. While one is active the setting
     * waits (WPStarter_Feature::replaced_active()); say so, with a
     * deactivate link where the user can deactivate it here.
     *
     * @param array $field Schema entry.
     */
    private static function render_replaces(array $field) {
        if (empty($field['replaces']) || !is_array($field['replaces'])) {
            return;
        }

        $active = WPStarter_Feature::active_plugins();
        $site   = self::active_plugins_by_slug();
        $items  = array();
        $links  = array();
        $busy   = array();
        foreach ($field['replaces'] as $slug => $name) {
            $items[] = esc_html($name);
            if (!isset($active[$slug])) {
                continue;
            }
            $busy[] = (string) $name;
            if (isset($site[$slug]) && current_user_can('deactivate_plugin', $site[$slug])) {
                // Comes back to this tab, where the setting then takes over.
                $url     = WPStarter_Replaced_Plugins::deactivate_url($site[$slug]);
                /* translators: %s: plugin name */
                $links[] = sprintf('<a href="%1$s">%2$s</a>', esc_url($url), esc_html(sprintf(__('Deactivate %s', 'wp-plugin-starter-template'), $name)));
            }
        }

        printf(
            '<p class="wps-replaces">%1$s %2$s</p>',
            esc_html__('Replaces:', 'wp-plugin-starter-template'),
            implode(', ', $items) // phpcs:ignore WordPress.Security.EscapeOutput -- escaped above.
        );
        if ($busy) {
            printf(
                '<p class="wps-replaces wps-replaces__active">%1$s %2$s</p>',
                /* translators: %s: plugin names */
                esc_html(sprintf(__('%s is still active, so it does this job and this setting waits until it is deactivated.', 'wp-plugin-starter-template'), implode(', ', $busy))),
                implode(' · ', $links) // phpcs:ignore WordPress.Security.EscapeOutput -- escaped above.
            );
        }
    }

    /**
     * Plugins active on this site (not network-wide) keyed by directory slug.
     *
     * @return array<string,string> slug => plugin file
     */
    private static function active_plugins_by_slug() {
        static $active = null;
        if (null === $active) {
            $active = array();
            foreach (WPStarter_Feature::stored_active_plugins() as $file) {
                $slug = dirname((string) $file);
                if ('.' !== $slug) {
                    $active[$slug] = (string) $file;
                }
            }
        }
        return $active;
    }

    /**
     * Render a child field row.
     *
     * @param string $key   Setting key.
     * @param array  $field Schema entry.
     */
    public static function render_field($key, array $field) {
        $value   = WPStarter_Settings::get($key);
        $id      = 'wps-' . $key;
        $desc_id = $id . '-desc';
        $attrs   = sprintf('id="%1$s" data-wps-setting="%2$s" aria-describedby="%3$s"', esc_attr($id), esc_attr($key), esc_attr($desc_id));
        $is_multi = 'multi' === $field['type'];
        ?>
        <div class="wps-field">
            <?php if ($is_multi) : ?>
                <span class="wps-field__label" id="<?php echo esc_attr($id); ?>-label"><?php echo esc_html($field['label']); ?></span>
            <?php else : ?>
                <label class="wps-field__label" for="<?php echo esc_attr($id); ?>"><?php echo esc_html($field['label']); ?></label>
            <?php endif; ?>
            <div class="wps-field__control">
                <?php
                switch ($field['type']) {
                    case 'select':
                        printf('<select %s>', $attrs); // phpcs:ignore WordPress.Security.EscapeOutput -- escaped above.
                        $choices = WPStarter_Settings::options_for($field);
                        if (!empty($field['open']) && '' !== (string) $value && !array_key_exists((string) $value, $choices)) {
                            // A saved choice whose plugin is not loaded here stays shown.
                            $choices[(string) $value] = (string) $value;
                        }
                        foreach ($choices as $option_value => $option_label) {
                            printf(
                                '<option value="%1$s"%2$s>%3$s</option>',
                                esc_attr((string) $option_value),
                                selected((string) $value, (string) $option_value, false),
                                esc_html($option_label)
                            );
                        }
                        echo '</select>';
                        break;

                    case 'multi':
                        $chosen  = array_map('strval', (array) $value);
                        $choices = WPStarter_Settings::options_for($field);
                        // With some plugins skipped on this request, a saved
                        // choice may belong to one of them; keep it too.
                        if (!empty($field['open']) || WPStarter_Feature::plugins_skipped()) {
                            // Saved items that are not registered right now stay visible so they can be unticked.
                            foreach (array_diff($chosen, array_map('strval', array_keys($choices))) as $missing) {
                                $choices[$missing] = $missing;
                            }
                        }
                        $long = count($choices) > 12;
                        if ($long) {
                            // Long lists (such as every active plugin) scroll, with quick choices.
                            printf(
                                '<span class="wps-checkboxes__all"><button type="button" class="button-link" data-wps-check-all="%1$s">%2$s</button> · <button type="button" class="button-link" data-wps-check-none="%1$s">%3$s</button></span>',
                                esc_attr($id),
                                esc_html__('Select all', 'wp-plugin-starter-template'),
                                esc_html__('Clear', 'wp-plugin-starter-template')
                            );
                        }
                        // The group carries data-wps-setting; the JS saves every checked value.
                        printf(
                            '<fieldset class="wps-checkboxes%3$s" data-wps-multi %1$s aria-labelledby="%2$s">',
                            $attrs, // phpcs:ignore WordPress.Security.EscapeOutput -- escaped above.
                            esc_attr($id . '-label'),
                            $long ? ' is-long' : ''
                        );
                        foreach ($choices as $option_value => $option_label) {
                            printf(
                                '<label class="wps-checkbox"><input type="checkbox" value="%1$s"%2$s /> %3$s</label>',
                                esc_attr((string) $option_value),
                                checked(in_array((string) $option_value, $chosen, true), true, false),
                                esc_html($option_label)
                            );
                        }
                        echo '</fieldset>';
                        break;

                    case 'url':
                        printf(
                            '<input type="text" class="regular-text code" inputmode="url" %1$s value="%2$s" placeholder="%3$s" />',
                            $attrs, // phpcs:ignore WordPress.Security.EscapeOutput -- escaped above.
                            esc_attr((string) $value),
                            esc_attr(isset($field['placeholder']) ? $field['placeholder'] : '')
                        );
                        break;

                    case 'times':
                        printf(
                            '<input type="text" class="regular-text" %1$s value="%2$s" placeholder="%3$s" autocomplete="off" />',
                            $attrs, // phpcs:ignore WordPress.Security.EscapeOutput -- escaped above.
                            esc_attr((string) $value),
                            esc_attr(isset($field['placeholder']) ? $field['placeholder'] : '')
                        );
                        break;

                    case 'int':
                        printf(
                            '<input type="number" class="small-text" %1$s value="%2$s" min="%3$s" max="%4$s" step="1" inputmode="numeric" />',
                            $attrs, // phpcs:ignore WordPress.Security.EscapeOutput -- escaped above.
                            esc_attr((string) $value),
                            esc_attr(isset($field['min']) ? (string) $field['min'] : ''),
                            esc_attr(isset($field['max']) ? (string) $field['max'] : '')
                        );
                        if (!empty($field['unit'])) {
                            echo ' <span class="wps-field__unit">' . esc_html($field['unit']) . '</span>';
                        }
                        break;

                    case 'lines':
                    case 'domains':
                        printf(
                            '<textarea class="large-text code" rows="%1$d" %2$s placeholder="%3$s">%4$s</textarea>',
                            isset($field['rows']) ? (int) $field['rows'] : 3,
                            $attrs, // phpcs:ignore WordPress.Security.EscapeOutput -- escaped above.
                            esc_attr(isset($field['placeholder']) ? $field['placeholder'] : ''),
                            esc_textarea((string) $value)
                        );
                        break;

                    case 'media':
                        // The hidden input carries data-wps-setting; the JS sets it
                        // from the media dialog and saves it.
                        $image_id = (int) $value;
                        $preview  = $image_id ? wp_get_attachment_image_url($image_id, 'thumbnail') : '';
                        echo '<div class="wps-media" data-wps-media>';
                        printf(
                            '<input type="hidden" data-wps-setting="%1$s" value="%2$s" />',
                            esc_attr($key),
                            esc_attr((string) $image_id)
                        );
                        if ($preview) {
                            printf('<img class="wps-media__preview" src="%s" alt="" />', esc_url($preview));
                        } else {
                            echo '<img class="wps-media__preview" alt="" hidden />';
                        }
                        printf(
                            '<button type="button" class="button wps-media__choose" id="%1$s" aria-describedby="%2$s">%3$s</button>',
                            esc_attr($id),
                            esc_attr($desc_id),
                            esc_html__('Choose picture', 'wp-plugin-starter-template')
                        );
                        printf(
                            '<button type="button" class="button-link wps-media__remove"%1$s>%2$s</button>',
                            $image_id ? '' : ' hidden',
                            esc_html__('Remove', 'wp-plugin-starter-template')
                        );
                        echo '</div>';
                        break;

                    case 'bool':
                        printf(
                            '<span class="wps-switch"><input type="checkbox" role="switch" class="wps-switch__input" %1$s %2$s /><span class="wps-switch__track" aria-hidden="true"></span></span>',
                            $attrs, // phpcs:ignore WordPress.Security.EscapeOutput -- escaped above.
                            checked((bool) $value, true, false)
                        );
                        break;

                    case 'text':
                    default:
                        printf(
                            '<input type="text" class="regular-text" %1$s value="%2$s" placeholder="%3$s" />',
                            $attrs, // phpcs:ignore WordPress.Security.EscapeOutput -- escaped above.
                            esc_attr((string) $value),
                            esc_attr(isset($field['placeholder']) ? $field['placeholder'] : '')
                        );
                        break;
                }
                ?>
                <span class="wps-status" data-wps-status="<?php echo esc_attr($key); ?>" aria-hidden="true"></span>
                <?php if (!empty($field['description']) || !empty($field['tokens'])) : ?>
                    <p class="description" id="<?php echo esc_attr($desc_id); ?>">
                        <?php echo esc_html(isset($field['description']) ? $field['description'] : ''); ?>
                        <?php if (!empty($field['tokens'])) : ?>
                            <span class="wps-tokens">
                                <?php esc_html_e('Tokens:', 'wp-plugin-starter-template'); ?>
                                <?php foreach ($field['tokens'] as $token) : ?>
                                    <button type="button" class="wps-token" data-token="<?php echo esc_attr($token); ?>" data-target="<?php echo esc_attr($id); ?>" title="<?php esc_attr_e('Insert token', 'wp-plugin-starter-template'); ?>"><code><?php echo esc_html($token); ?></code></button>
                                <?php endforeach; ?>
                            </span>
                        <?php endif; ?>
                    </p>
                <?php endif; ?>
            </div>
        </div>
        <?php
    }
}
