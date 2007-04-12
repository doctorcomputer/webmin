#!/usr/local/bin/perl
# upload.cgi
# Upload a file

require './file-lib.pl';
$disallowed_buttons{'upload'} && &error($text{'ebutton'});
&popup_header();
&ReadParse(\%getin, "GET");
$upid = $getin{'id'};
&ReadParseMime($upload_max, \&read_parse_mime_callback, [ $upid ]);

$realdir = &unmake_chroot($in{'dir'});
if (!$in{'file_filename'}) {
	print "<p><b>$text{'upload_efile'}</b><p>\n";
	}
elsif (!-d $realdir) {
	print "<p><b>$text{'upload_edir'}</b><p>\n";
	}
else {
	$in{'file_filename'} =~ /([^\\\/]+)$/;
	$path = "$in{'dir'}/$1";
	$realpath = "$realdir/$1";
	if (-e $realpath) {
		# File exists .. ask the user if he is sure
		&switch_acl_uid();
		$temp = &tempname();
		&open_tempfile(TEMP, ">$temp");
		if ($dostounix == 1 && $in{'dos'}) {
			$in{'file'} =~ s/\r\n/\n/g;
			}
		&print_tempfile(TEMP, $in{'file'});
		&close_tempfile(TEMP);
		print "<form action=upload2.cgi>\n";
		foreach $i (keys %prein) {
			print "<input type=hidden name=$i value='",
				&html_escape($prein{$i}),"'>\n";
			}
		print "<input type=hidden name=dir value='",
			&html_escape($in{'dir'}),"'>\n";
		print "<input type=hidden name=path value='",
			&html_escape($path),"'>\n";
		print "<input type=hidden name=temp value='",
			&html_escape($temp),"'>\n";
		print "<input type=hidden name=zip value='",
			&html_escape($in{'zip'}),"'>\n";
		print "<center>\n";
		print &text('upload_already', "<tt>$path</tt>"),"<p>\n";
		print "<input type=submit name=yes value='$text{'yes'}'>\n";
		print "<input type=submit name=no value='$text{'no'}'>\n";
		print "</form>\n";
		}
	else {
		# Go ahread and do it!
		&webmin_log("upload", undef, $path);
		&switch_acl_uid();
		if ($access{'ro'} || !&can_access($path)) {
			print "<p><b>",&text('upload_eperm', $path),"</b><p>\n";
			}
		elsif (-l $path && !&must_follow($realpath)) {
			print "<p><b>",&text('upload_elink', $path),"</b><p>\n";
			}
		elsif (!&open_tempfile(FILE, ">$realpath", 1)) {
			print "<p><b>",&text('upload_ewrite', $path, $!),"</b><p>\n";
			}
		else {
			if ($dostounix == 1 && $in{'dos'}) {
				$in{'file'} =~ s/\r\n/\n/g;
				}
			&print_tempfile(FILE, $in{'file'});
			&close_tempfile(FILE);
			&post_upload($path, $in{'dir'}, $in{'zip'});
			}
		}
	}

&popup_footer();
