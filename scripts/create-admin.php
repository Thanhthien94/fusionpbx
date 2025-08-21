<?php
/*
 * Create FusionPBX admin user following official installation pattern
 * Based on fusionpbx-install.sh/debian/resources/finish.sh
 */

// Set error reporting
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Get environment variables
$domain_name = getenv('FUSIONPBX_DOMAIN') ?: 'localhost';
$admin_username = getenv('FUSIONPBX_ADMIN_USER') ?: 'admin';
$admin_password = getenv('FUSIONPBX_ADMIN_PASSWORD') ?: 'admin';

// Database connection details
$db_host = getenv('DB_HOST') ?: 'localhost';
$db_port = getenv('DB_PORT') ?: '5432';
$db_name = getenv('DB_NAME') ?: 'fusionpbx';
$db_user = getenv('DB_USER') ?: 'fusionpbx';
$db_password = getenv('DB_PASSWORD') ?: 'fusionpbx';

echo "Creating FusionPBX admin user (official method)...\n";
echo "Domain: $domain_name\n";
echo "Username: $admin_username\n";

// Retry logic for database connection
$max_retries = 10;
$retry_delay = 3;

for ($i = 0; $i < $max_retries; $i++) {
    try {
        // Connect to database
        $dsn = "pgsql:host=$db_host;port=$db_port;dbname=$db_name";
        $pdo = new PDO($dsn, $db_user, $db_password);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        echo "✅ Database connection established\n";
        break;
    } catch (Exception $e) {
        echo "⚠️ Database connection attempt " . ($i + 1) . "/$max_retries failed: " . $e->getMessage() . "\n";
        if ($i == $max_retries - 1) {
            echo "❌ Failed to connect to database after $max_retries attempts\n";
            exit(1);
        }
        echo "Retrying in $retry_delay seconds...\n";
        sleep($retry_delay);
    }
}

try {
    
    // Generate UUIDs (simple UUID v4 generation)
    function generate_uuid() {
        return sprintf('%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
            mt_rand(0, 0xffff), mt_rand(0, 0xffff),
            mt_rand(0, 0xffff),
            mt_rand(0, 0x0fff) | 0x4000,
            mt_rand(0, 0x3fff) | 0x8000,
            mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
        );
    }
    
    // Check if domain exists
    $stmt = $pdo->prepare("SELECT domain_uuid FROM v_domains WHERE domain_name = ?");
    $stmt->execute([$domain_name]);
    $domain_uuid = $stmt->fetchColumn();
    
    if (!$domain_uuid) {
        echo "Creating domain: $domain_name\n";
        $domain_uuid = generate_uuid();
        $stmt = $pdo->prepare("INSERT INTO v_domains (domain_uuid, domain_name, domain_enabled) VALUES (?, ?, 'true')");
        $stmt->execute([$domain_uuid, $domain_name]);
    }
    
    // Check if user exists
    $stmt = $pdo->prepare("SELECT user_uuid FROM v_users WHERE username = ? AND domain_uuid = ?");
    $stmt->execute([$admin_username, $domain_uuid]);
    $user_uuid = $stmt->fetchColumn();
    
    if (!$user_uuid) {
        echo "Creating admin user: $admin_username\n";
        
        // Generate user data (following official pattern)
        $user_uuid = generate_uuid();
        $user_salt = generate_uuid();
        $password_hash = md5($user_salt . $admin_password);
        
        // Insert user (following official finish.sh pattern)
        $stmt = $pdo->prepare("INSERT INTO v_users (user_uuid, domain_uuid, username, password, salt, user_enabled) VALUES (?, ?, ?, ?, ?, 'true')");
        $stmt->execute([$user_uuid, $domain_uuid, $admin_username, $password_hash, $user_salt]);
        
        echo "✅ Admin user created successfully!\n";
        echo "Login: $admin_username@$domain_name\n";
        echo "Password: $admin_password\n";
    } else {
        echo "Admin user already exists\n";
    }
    
    // Always check and assign superadmin group (even if user exists)
    echo "Checking superadmin group assignment...\n";

    // First, ensure we have the user_uuid
    if (!$user_uuid) {
        $stmt = $pdo->prepare("SELECT user_uuid FROM v_users WHERE username = ? AND domain_uuid = ?");
        $stmt->execute([$admin_username, $domain_uuid]);
        $user_uuid = $stmt->fetchColumn();
    }

    if (!$user_uuid) {
        echo "❌ Cannot find user UUID for group assignment\n";
    } else {
        echo "User UUID: $user_uuid\n";

        // Wait for groups table to be ready and populated
        $groups_ready = false;
        for ($i = 0; $i < 10; $i++) {
            try {
                $stmt = $pdo->prepare("SELECT COUNT(*) FROM v_groups WHERE group_name = 'superadmin'");
                $stmt->execute();
                $group_count = $stmt->fetchColumn();
                if ($group_count > 0) {
                    $groups_ready = true;
                    echo "✅ Groups table ready with $group_count superadmin groups\n";
                    break;
                }
                echo "⚠️ Groups table not ready (attempt " . ($i + 1) . "/10), waiting...\n";
            } catch (Exception $e) {
                echo "⚠️ Groups table error: " . $e->getMessage() . "\n";
            }
            sleep(3);
        }

        if (!$groups_ready) {
            echo "❌ Groups table not ready after 10 attempts, forcing group creation...\n";

            // Try to create superadmin group if it doesn't exist
            try {
                $superadmin_group_uuid = generate_uuid();
                $stmt = $pdo->prepare("INSERT INTO v_groups (group_uuid, domain_uuid, group_name, group_level, group_description, group_protected) VALUES (?, ?, 'superadmin', '10', 'Super Administrator', 'true') ON CONFLICT (group_name, domain_uuid) DO NOTHING");
                $stmt->execute([$superadmin_group_uuid, $domain_uuid]);
                echo "✅ Superadmin group created/ensured\n";
                $groups_ready = true;
            } catch (Exception $e) {
                echo "❌ Failed to create superadmin group: " . $e->getMessage() . "\n";
            }
        }

        if ($groups_ready) {
            // Check current group assignment
            $stmt = $pdo->prepare("SELECT COUNT(*) FROM v_user_groups WHERE user_uuid = ? AND group_name = 'superadmin'");
            $stmt->execute([$user_uuid]);
            $has_superadmin = $stmt->fetchColumn();

            echo "Current superadmin assignments for user: $has_superadmin\n";

            if (!$has_superadmin) {
                echo "Assigning superadmin group...\n";

                // Get superadmin group UUID
                $stmt = $pdo->prepare("SELECT group_uuid FROM v_groups WHERE group_name = 'superadmin' LIMIT 1");
                $stmt->execute();
                $group_uuid = $stmt->fetchColumn();

                if ($group_uuid) {
                    echo "Found superadmin group UUID: $group_uuid\n";

                    // Add user to superadmin group (following official pattern)
                    $user_group_uuid = generate_uuid();
                    try {
                        $stmt = $pdo->prepare("INSERT INTO v_user_groups (user_group_uuid, domain_uuid, group_name, group_uuid, user_uuid) VALUES (?, ?, 'superadmin', ?, ?)");
                        $stmt->execute([$user_group_uuid, $domain_uuid, $group_uuid, $user_uuid]);
                        echo "✅ User added to superadmin group\n";

                        // Verify assignment
                        $stmt = $pdo->prepare("SELECT COUNT(*) FROM v_user_groups WHERE user_uuid = ? AND group_name = 'superadmin'");
                        $stmt->execute([$user_uuid]);
                        $verify_count = $stmt->fetchColumn();
                        if ($verify_count > 0) {
                            echo "✅ Superadmin group assignment verified (count: $verify_count)\n";

                            // Also verify with detailed query
                            $stmt = $pdo->prepare("SELECT ug.group_name, g.group_level FROM v_user_groups ug JOIN v_groups g ON ug.group_uuid = g.group_uuid WHERE ug.user_uuid = ?");
                            $stmt->execute([$user_uuid]);
                            $user_groups = $stmt->fetchAll(PDO::FETCH_ASSOC);
                            echo "User groups: " . json_encode($user_groups) . "\n";
                        } else {
                            echo "❌ Failed to verify superadmin group assignment\n";
                        }
                    } catch (Exception $e) {
                        echo "❌ Error assigning superadmin group: " . $e->getMessage() . "\n";
                    }
                } else {
                    echo "❌ Warning: superadmin group UUID not found\n";
                }
            } else {
                echo "✅ User already has superadmin permissions (count: $has_superadmin)\n";
            }
        }
    }
    
} catch (Exception $e) {
    echo "❌ Error creating admin user: " . $e->getMessage() . "\n";
    exit(1);
}

echo "✅ Admin user setup completed\n";
?>
