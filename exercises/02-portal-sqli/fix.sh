#!/usr/bin/env bash
# Run this ON target (vagrant ssh target) to remediate exercise 02: moves
# the portal's login query to a prepared statement (real code fix, not a
# config toggle) and adds a file-extension allowlist to the document
# upload. Re-run exercises/02-portal-sqli/README.md's Step 2 afterwards
# to confirm both no longer work.
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"

PORTAL_DIR=/var/www/html/legacy

cat > "${PORTAL_DIR}/login.php" <<'PHP'
<?php
session_start();
require __DIR__ . '/db.php';
$error = '';
if (isset($_REQUEST['username'])) {
    $u = $_REQUEST['username'] ?? '';
    $p = $_REQUEST['password'] ?? '';
    // Fixed: prepared statement, no string concatenation into the query.
    $stmt = $mysqli->prepare('SELECT * FROM users WHERE username=? AND password=?');
    $stmt->bind_param('ss', $u, $p);
    $stmt->execute();
    $result = $stmt->get_result();
    if ($result && $result->num_rows > 0) {
        $row = $result->fetch_assoc();
        $_SESSION['user'] = $row['username'];
        header('Location: dashboard.php');
        exit;
    }
    $error = 'Login failed.';
}
?>
<!doctype html><html><head><title>Northgate Employee Portal</title>
<link rel="stylesheet" href="style.css"></head><body>
<div class="topbar">Northgate Defense Systems &mdash; Employee Portal (legacy)</div>
<div class="box">
<h1>Employee Sign In</h1>
<p class="sub">Internal use only. Contact IT if you've forgotten your login.</p>
<form method="post">
<label>Username</label><input type="text" name="username">
<label>Password</label><input type="password" name="password">
<input type="submit" value="Sign in">
</form>
<?php if ($error): ?><div class="msg"><?= htmlspecialchars($error) ?></div><?php endif; ?>
</div>
</body></html>
PHP

cat > "${PORTAL_DIR}/dashboard.php" <<'PHP'
<?php
session_start();
if (!isset($_SESSION['user'])) { header('Location: login.php'); exit; }
$msg = '';
$allowed = ['jpg','jpeg','png','pdf','docx','txt'];
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['document'])) {
    $name = basename($_FILES['document']['name']);
    $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
    if (!in_array($ext, $allowed, true)) {
        $msg = "Rejected: file type .$ext is not allowed.";
    } else {
        $dest = __DIR__ . '/uploads/' . $name;
        if (move_uploaded_file($_FILES['document']['tmp_name'], $dest)) {
            $msg = "Uploaded: $name";
        }
    }
}
?>
<!doctype html><html><head><title>Dashboard - Northgate Employee Portal</title>
<link rel="stylesheet" href="style.css"></head><body>
<div class="topbar">Northgate Defense Systems &mdash; Employee Portal (legacy)</div>
<div class="dash">
<h1>Welcome, <?= htmlspecialchars($_SESSION['user']) ?></h1>
<p><a href="logout.php">Log out</a></p>
<h2 style="font-size:1em;">Submit a document</h2>
<form method="post" enctype="multipart/form-data">
<input type="file" name="document">
<input type="submit" value="Upload">
</form>
<?php if ($msg): ?><p><?= htmlspecialchars($msg) ?></p><?php endif; ?>
</div>
</body></html>
PHP

chown www-data:www-data "${PORTAL_DIR}/login.php" "${PORTAL_DIR}/dashboard.php"

echo "Fixed: the portal's login now uses a prepared statement and the upload only accepts jpg/jpeg/png/pdf/docx/txt on $(hostname)."
