#!/usr/local/bin/perl
# Show a list of blocked users and hosts

require './usermin-lib.pl';
&ui_print_header(undef, $text{'blocked_title'}, "");
&get_usermin_miniserv_config(\%miniserv);
@blocked = &webmin::get_blocked_users_hosts(\%miniserv);

if (@blocked) {
	print &ui_columns_start([ $webmin::text{'blocked_type'},
				  $text{'blocked_who'},
				  $webmin::text{'blocked_fails'},
				  $webmin::text{'blocked_when'},
				]);
	foreach $b (@blocked) {
		print &ui_columns_row([
			$text{'blocked_'.$b->{'type'}},
			$b->{'user'} || $b->{'host'},
			$b->{'fails'},
			&make_date($b->{'when'}),
			]);
		}
	print &ui_columns_end();
	print "<hr>\n";
	print &ui_buttons_start();
	print &ui_buttons_row("clear_blocked.cgi",
			      $webmin::text{'blocked_clear'},
			      $text{'blocked_cleardesc'});
	print &ui_buttons_end();
	}
else {
	print "<b>$text{'blocked_none'}</b><p>\n";
	}

&ui_print_footer("", $text{'index_return'});
