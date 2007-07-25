#!/usr/local/bin/perl
# Show a page for just adding, editing or removing an autoreply message

require './filter-lib.pl';
&ReadParse();

&ui_print_header(undef, $text{'auto_title'}, "");

# Get the autoreply filter, if any
@filters = &list_filters();
($filter) = grep { $_->{'actionreply'} } @filters;

print &ui_form_start("save_auto.cgi", "post");
print &ui_table_start($text{'auto_header'}, "width=100%", 2);

# Autoreply enabled?
print &ui_table_row($text{'auto_enabled'},
	&ui_yesno_radio("enabled", $filter ? 1 : 0));

# Message
print &ui_table_row($text{'auto_reply'},
	&ui_textarea("reply", $filter->{'reply'}->{'autotext'}, 5, 80));

# Period
$r = $filter->{'reply'};
$period = $r->{'replies'} && $r->{'period'} ? int($r->{'period'}/60) :
	  $r->{'replies'} ? 60 : undef;
print &ui_table_row($text{'auto_period'},
	&ui_opt_textbox("period", $period, 3, $text{'index_noperiod'}).
	" ".$text{'index_mins'});

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});
