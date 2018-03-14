<?php
	$handle = opendir('packages');
	while ( ($entry = readdir($handle)) !== false) {
		echo "$entry\n";
	}
	closedir($handle);
?>
