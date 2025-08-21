<?php
/*
 * Debug FusionPBX User Groups
 * Check user permissions and group assignments
 */

// Set error reporting
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Get environment variables
$domain_name = getenv('FUSIONPBX_DOMAIN') ?: 'localhost';
$admin_username = getenv('FUSIONPBX_ADMIN_USER') ?: 'admin';

// Database connection details
$db_host = getenv('DB_HOST') ?: 'localhost';
$db_port = getenv('DB_PORT') ?: '5432';
$db_name = getenv('DB_NAME') ?: 'fusionpbx';
$db_user = getenv('DB_USER') ?: 'fusionpbx';
$db_password = getenv('DB_PASSWORD') ?: 'fusionpbx';

echo "=== FusionPBX User Groups Debug ===\n";
echo "Domain: $domain_name\n";
echo "Admin User: $admin_username\n";
echo "Database: $db_name\n\n";

try {
    // Connect to database
    $dsn = "pgsql:host=$db_host;port=$db_port;dbname=$db_name";
    $pdo = new PDO($dsn, $db_user, $db_password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    echo "✅ Database connection established\n\n";
    
    // 1. Check domains
    echo "=== DOMAINS ===\n";
    $stmt = $pdo->prepare("SELECT domain_uuid, domain_name, domain_enabled FROM v_domains ORDER BY domain_name");
    $stmt->execute();
    $domains = $stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($domains as $domain) {
        echo "Domain: {$domain['domain_name']} (UUID: {$domain['domain_uuid']}, Enabled: {$domain['domain_enabled']})\n";
    }
    echo "\n";
    
    // 2. Check users
    echo "=== USERS ===\n";
    $stmt = $pdo->prepare("SELECT u.user_uuid, u.username, u.user_enabled, d.domain_name FROM v_users u JOIN v_domains d ON u.domain_uuid = d.domain_uuid ORDER BY u.username");
    $stmt->execute();
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($users as $user) {
        echo "User: {$user['username']}@{$user['domain_name']} (UUID: {$user['user_uuid']}, Enabled: {$user['user_enabled']})\n";
    }
    echo "\n";
    
    // 3. Check groups
    echo "=== GROUPS ===\n";
    $stmt = $pdo->prepare("SELECT group_uuid, group_name, group_level, group_description, domain_uuid FROM v_groups ORDER BY group_level DESC, group_name");
    $stmt->execute();
    $groups = $stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($groups as $group) {
        echo "Group: {$group['group_name']} (Level: {$group['group_level']}, UUID: {$group['group_uuid']})\n";
        echo "  Description: {$group['group_description']}\n";
    }
    echo "\n";
    
    // 4. Check user groups
    echo "=== USER GROUPS ===\n";
    $stmt = $pdo->prepare("
        SELECT 
            u.username,
            d.domain_name,
            ug.group_name,
            g.group_level,
            g.group_description
        FROM v_user_groups ug
        JOIN v_users u ON ug.user_uuid = u.user_uuid
        JOIN v_domains d ON u.domain_uuid = d.domain_uuid
        JOIN v_groups g ON ug.group_uuid = g.group_uuid
        ORDER BY u.username, g.group_level DESC
    ");
    $stmt->execute();
    $user_groups = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    if (empty($user_groups)) {
        echo "❌ NO USER GROUPS FOUND!\n";
    } else {
        foreach ($user_groups as $ug) {
            echo "User: {$ug['username']}@{$ug['domain_name']} → Group: {$ug['group_name']} (Level: {$ug['group_level']})\n";
        }
    }
    echo "\n";
    
    // 5. Check specific admin user
    echo "=== ADMIN USER DETAILS ===\n";
    $stmt = $pdo->prepare("
        SELECT 
            u.user_uuid,
            u.username,
            u.user_enabled,
            d.domain_name,
            d.domain_uuid
        FROM v_users u 
        JOIN v_domains d ON u.domain_uuid = d.domain_uuid 
        WHERE u.username = ? AND d.domain_name = ?
    ");
    $stmt->execute([$admin_username, $domain_name]);
    $admin_user = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if ($admin_user) {
        echo "Admin User Found:\n";
        echo "  Username: {$admin_user['username']}\n";
        echo "  Domain: {$admin_user['domain_name']}\n";
        echo "  User UUID: {$admin_user['user_uuid']}\n";
        echo "  Domain UUID: {$admin_user['domain_uuid']}\n";
        echo "  Enabled: {$admin_user['user_enabled']}\n";
        
        // Check admin user groups
        echo "\nAdmin User Groups:\n";
        $stmt = $pdo->prepare("
            SELECT 
                ug.group_name,
                g.group_level,
                g.group_description,
                ug.user_group_uuid
            FROM v_user_groups ug
            JOIN v_groups g ON ug.group_uuid = g.group_uuid
            WHERE ug.user_uuid = ?
            ORDER BY g.group_level DESC
        ");
        $stmt->execute([$admin_user['user_uuid']]);
        $admin_groups = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        if (empty($admin_groups)) {
            echo "  ❌ NO GROUPS ASSIGNED TO ADMIN USER!\n";
        } else {
            foreach ($admin_groups as $group) {
                echo "  ✅ {$group['group_name']} (Level: {$group['group_level']})\n";
            }
        }
    } else {
        echo "❌ Admin user not found: $admin_username@$domain_name\n";
    }
    echo "\n";
    
    // 6. Check permissions
    echo "=== GROUP PERMISSIONS ===\n";
    $stmt = $pdo->prepare("SELECT group_name, permission_name FROM v_group_permissions WHERE group_name = 'superadmin' LIMIT 10");
    $stmt->execute();
    $permissions = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    if (empty($permissions)) {
        echo "❌ NO PERMISSIONS FOUND FOR SUPERADMIN GROUP!\n";
    } else {
        echo "Superadmin permissions (first 10):\n";
        foreach ($permissions as $perm) {
            echo "  - {$perm['permission_name']}\n";
        }
        
        // Count total permissions
        $stmt = $pdo->prepare("SELECT COUNT(*) FROM v_group_permissions WHERE group_name = 'superadmin'");
        $stmt->execute();
        $total_perms = $stmt->fetchColumn();
        echo "  Total superadmin permissions: $total_perms\n";
    }
    echo "\n";
    
    // 7. Check menu items
    echo "=== MENU ITEMS ===\n";
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM v_menu_items");
    $stmt->execute();
    $menu_count = $stmt->fetchColumn();
    echo "Total menu items: $menu_count\n";
    
    if ($menu_count == 0) {
        echo "❌ NO MENU ITEMS FOUND!\n";
    }
    echo "\n";
    
    // 8. Recommendations
    echo "=== RECOMMENDATIONS ===\n";
    
    if (empty($user_groups)) {
        echo "❌ CRITICAL: No user groups assigned. Run upgrade.php --permissions\n";
    }
    
    if ($admin_user && empty($admin_groups)) {
        echo "❌ CRITICAL: Admin user has no groups. Need to assign superadmin group.\n";
    }
    
    if (empty($permissions)) {
        echo "❌ CRITICAL: No permissions found. Run upgrade.php --permissions\n";
    }
    
    if ($menu_count == 0) {
        echo "❌ CRITICAL: No menu items. Run upgrade.php --menu\n";
    }
    
    echo "\n=== DEBUG COMPLETED ===\n";
    
} catch (Exception $e) {
    echo "❌ Error: " . $e->getMessage() . "\n";
    exit(1);
}
?>
