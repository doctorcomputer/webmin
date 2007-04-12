#!/usr/local/bin/perl
# delete_mail.cgi
# Delete, mark, move or copy multiple messages

require './mailboxes-lib.pl';
&ReadParse();
&can_user($in{'user'}) || &error($text{'mail_ecannot'});
@delete = sort { $a <=> $b } split(/\0/, $in{'d'});
@folders = &list_user_folders($in{'user'});
$folder = $folders[$in{'folder'}];

if ($in{'mark1'} || $in{'mark2'}) {
	# Marking emails with some status
	@delete || &error($text{'delete_emnone'});
	@mail = &mailbox_list_mails($delete[0], $delete[@delete-1], $folder);
	dbmopen(%read, "$module_config_directory/$in{'user'}.read", 0600);
	local $m = $in{'mark1'} ? $in{'mode1'} : $in{'mode2'};
	foreach $d (@delete) {
		local $hid = $mail[$d]->{'header'}->{'message-id'};
		if ($m) {
			$read{$hid} = $m;
			}
		else {
			delete($read{$hid});
			}
		}
	dbmclose(%read);
	$perpage = $folder->{'perpage'} || $config{'perpage'};
	&redirect("list_mail.cgi?start=$in{'start'}&folder=$in{'folder'}&user=$in{'user'}");
	}
elsif ($in{'move1'} || $in{'move2'}) {
	# Moving mails to some other user's inbox
	&check_modification($folder);
	@delete || &error($text{'delete_emovenone'});
	$muser = $in{'move1'} ? $in{'mfolder1'} : $in{'mfolder2'};
	&can_user($muser) || &error($text{'delete_emovecannot'});
	@mfolders = &list_user_folders($muser);
	@mfolders || &error($text{'delete_emoveuser'});

	@mail = &mailbox_list_mails($delete[0], $delete[@delete-1], $folder);
	foreach $d (@delete) {
		$mail[$d] || &error($text{'mail_eexists'});
		push(@movemail, $mail[$d]);
		}
	&lock_folder($folder);
	&lock_folder($mfolder);
	&mailbox_move_mail($folder, $mfolders[0], @movemail);
	&unlock_folder($mfolder);
	&unlock_folder($folder);
	&webmin_log("movemail", undef, undef, { 'from' => $folder->{'file'},
						'to' => $mfolders[0]->{'file'},
						'count' => scalar(@delete) } );
	&redirect("list_mail.cgi?start=$in{'start'}&folder=$in{'folder'}&user=$in{'user'}");
	}
elsif ($in{'copy1'} || $in{'copy2'}) {
	# Copying mails to some other folder
	@delete || &error($text{'delete_ecopynone'});
	$cuser = $in{'copy1'} ? $in{'mfolder1'} : $in{'mfolder2'};
	&can_user($cuser) || &error($text{'delete_ecopycannot'});
	@cfolders = &list_user_folders($cuser);
	@cfolders || &error($text{'delete_ecopyuser'});

	@mail = &mailbox_list_mails($delete[0], $delete[@delete-1], $folder);
	foreach $d (@delete) {
		$mail[$d] || &error($text{'mail_eexists'});
		push(@copymail, $mail[$d]);
		}
	&lock_folder($cfolder);
	&mailbox_copy_mail($folder, $cfolders[0], @copymail);
	&unlock_folder($cfolder);
	&webmin_log("copymail", undef, undef, { 'from' => $folder->{'file'},
						'to' => $cfolders[0]->{'file'},
						'count' => scalar(@delete) } );
	&redirect("list_mail.cgi?start=$in{'start'}&folder=$in{'folder'}&user=$in{'user'}");
	}
elsif ($in{'forward'}) {
	# Forwarding selected mails .. redirect
	@delete || &error($text{'delete_efnone'});
	&redirect("reply_mail.cgi?folder=$in{'folder'}&user=$in{'user'}&".
		  join("&", map { "mailforward=$_" } @delete));
	}
elsif ($in{'new'}) {
	# Need to redirect to compose form
	&redirect("reply_mail.cgi?new=1&folder=$in{'folder'}&user=$in{'user'}");
	}
elsif ($in{'black'}) {
	# Deny all senders
	@delete || &error($text{'delete_ebnone'});
	@mail = &mailbox_list_mails($delete[0], $delete[@delete-1], $folder);
	foreach $d (@delete) {
		push(@addrs, map { $_->[0] } &split_addresses($mail[$d]->{'header'}->{'from'}));
		}
	&foreign_require("spam", "spam-lib.pl");
	local $conf = &spam::get_config();
	local @from = map { @{$_->{'words'}} }
			  &spam::find("blacklist_from", $conf);
	local %already = map { $_, 1 } @from;
	@newaddrs = grep { !$already{$_} } &unique(@addrs);
	push(@from, @newaddrs);
	&spam::save_directives($conf, 'blacklist_from',
			       \@from, 1);
	&flush_file_lines();
	&redirect("list_mail.cgi?start=$in{'start'}&folder=$in{'folder'}&user=$in{'user'}");
	}
elsif ($in{'razor'}) {
	# Report all messages, and show output to the user
	@delete || &error($text{'delete_ebnone'});

	&ui_print_header(undef, $text{'razor_title'}, "");
	print "<b>$text{'razor_report2'}</b>\n";
	print "<pre>";

	# Write all messages to a temp file
	@mail = &mailbox_list_mails($delete[0], $delete[@delete-1], $folder);
	$temp = &transname();
	$cmd = &spam_report_cmd($in{'user'});
	foreach $d (@delete) {
		$mail[$d] || &error($text{'mail_eexists'});
		&send_mail($mail[$d], $temp);
		push(@delmail, $mail[$d]);
		}

	# Call reporting command on them
	&open_execute_command(OUT, "$cmd <$temp 2>&1", 1);
	local $error;
	while(<OUT>) {
		print &html_escape($_);
		$error++ if (/failed/i);
		}
	close(OUT);
	unlink($temp);
	print "</pre>\n";
	if ($? || $error) {
		print "<b>$text{'razor_err'}</b><p>\n";
		}
	else {
		if ($config{'spam_del'}) {
			# Delete spam too
			&lock_folder($folder);
			&mailbox_delete_mail($folder, @delmail);
			&unlock_folder($folder);
			print "<b>$text{'razor_deleted'}</b><p>\n";
			}
		else {
			print "<b>$text{'razor_done'}</b><p>\n";
			}
		}
	&ui_print_footer("list_mail.cgi?folder=$in{'folder'}&user=$in{'user'}", $text{'mail_return'}, "", $text{'index_return'});
	}
elsif ($in{'delete'} || $in{'deleteall'}) {
	# Just deleting emails
	&check_modification($folder);
	@delete || $in{'deleteall'} || &error($text{'delete_enone'});
	if (!$in{'confirm'} && &need_delete_warn($folder)) {
		# Need to ask for confirmation before deleting
		&ui_print_header(undef, $text{'confirm_title'}, "");
		print &check_clicks_function();

		print "<form action=delete_mail.cgi method=post>\n";
		foreach $i (keys %in) {
			foreach $v (split(/\0/, $in{$i})) {
				print "<input type=hidden name=$i value='",
				      &html_escape($v),"'>\n";
				}
			}
		print "<center><b>\n";
		if ($in{'deleteall'}) {
			print &text('confirm_warnall'),"<br>\n";
			}
		else {
			print &text('confirm_warn', scalar(@delete)),"<br>\n";
			}
		if ($config{'delete_warn'} ne 'y') {
			print "$text{'confirm_warn2'}<p>\n"
			}
		else {
			print "$text{'confirm_warn4'}<p>\n"
			}
		print "</b><p><input type=submit name=confirm ",
		      "value='$text{'confirm_ok'}' ",
		      "onClick='return check_clicks(form)'></center></form>\n";
		
		&ui_print_footer("list_mail.cgi?start=$in{'start'}&folder=$in{'folder'}&user=$in{'user'}", $text{'mail_return'});
		}
	else {
		# Go ahead and delete
		&lock_folder($folder);
		if ($in{'deleteall'}) {
			# Clear the whole folder
			$delcount = &mailbox_folder_size($folder);
			&mailbox_empty_folder($folder);
			}
		else {
			# Just delete selected messages
			@mail = &mailbox_list_mails($delete[0],
						    $delete[@delete-1],
						    $folder);
			foreach $d (@delete) {
				$mail[$d] || &error($text{'mail_eexists'});
				push(@delmail, $mail[$d]);
				}
			&mailbox_delete_mail($folder, @delmail);
			$delcount = scalar(@delmail);
			}
		&unlock_folder($folder);
		&webmin_log("delmail", undef, undef,
			    { 'from' => $folder->{'file'},
			      'all' => $in{'deleteall'},
			      'count' => $delcount } );
		&redirect("list_mail.cgi?start=$in{'start'}&folder=$in{'folder'}&user=$in{'user'}");
		}
	}
&pop3_logout_all();
