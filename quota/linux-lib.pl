# linux-lib.pl
# Quota functions for all linux version

# Tell the mount module not to check which filesystems are supported,
# as we don't care for the calls made by this module
$mount::no_check_support = 1;

# Pass UIDs and GIDs to edquota instead of names
$edquota_use_ids = 1;

# quotas_init()
sub quotas_init
{
if (&has_command("quotaon") && &has_command("quotaoff")) {
	return undef;
	}
else {
	return "The quotas package does not appear to be installed on ".
	       "your system\n";
	}
}

# quotas_supported()
# Returns 1 for user quotas, 2 for group quotas or 3 for both
sub quotas_supported
{
return 3;
}

# free_space(filesystem, [blocksize])
# Returns an array containing  btotal, bfree, ftotal, ffree
sub free_space
{
local(@out, @rv);
$out = `df -k $_[0]`;
$out =~ /Mounted on\n\S+\s+(\d+)\s+\d+\s+(\d+)/;
if ($_[1]) {
	push(@rv, int($1*1024/$_[1]), int($2*1024/$_[1]));
	}
else {
	push(@rv, $1, $2);
	}
$out = `df -i $_[0]`;
$out =~ /Mounted on\n\S+\s+(\d+)\s+\d+\s+(\d+)/;
push(@rv, $1, $2);
return @rv;
}

# quota_can(&mnttab, &fstab)
# Can this filesystem type support quotas?
#  0 = No quota support (or not turned on in /etc/fstab)
#  1 = User quotas only
#  2 = Group quotas only
#  3 = User and group quotas
sub quota_can
{
return ($_[1]->[3] =~ /usrquota|usrjquota/ ||
	$_[0]->[3] =~ /usrquota|usrjquota/ ? 1 : 0) +
       ($_[1]->[3] =~ /grpquota|grpjquota/ ||
        $_[0]->[3] =~ /grpquota|grpjquota/ ? 2 : 0);
}

# quota_now(&mnttab, &fstab)
# Are quotas currently active?
#  0 = Not active
#  1 = User quotas active
#  2 = Group quotas active
#  3 = Both active
# Adding 4 means they cannot be turned off (such as for XFS)
sub quota_now
{
local $rv = 0;
local $dir = $_[0]->[0];
local %opts = map { $_, 1 } split(/,/, $_[0]->[3]);
if ($_[0]->[2] eq "xfs") {
	# For XFS, assume enabled if setup in fstab
	$rv += 1 if ($opts{'quota'} || $opts{'usrquota'} ||
		     $opts{'uqnoenforce'});
	$rv += 2 if ($opts{'grpquota'} || $opts{'gqnoenforce'});
	return $rv + 4;
	}
if ($_[0]->[4]%2 == 1) {
	# test user quotas
	if (-r "$dir/quota.user" || -r "$dir/aquota.user") {
		local $stout = &supports_status($dir, "user");
		if ($stout =~ /is\s+(on|off)/) {
			# Can use output from -p mode
			if ($stout =~ /is\s+on/) {
				$rv += 1;
				}
			}
		else {
			# Fall back to testing by running quotaon
			$out = `$config{'user_quotaon_command'} $dir 2>&1`;
			if ($out =~ /Device or resource busy/i) {
				# already on..
				$rv += 1;
				}
			elsif ($out =~ /Package not installed/i) {
				# No quota support!
				return 0;
				}
			else {
				# was off.. need to turn on again
				`$config{'user_quotaoff_command'} $dir 2>&1`;
				}
			}
		}
	}
if ($_[0]->[4] > 1) {
	# test group quotas
	if (-r "$dir/quota.group" || -r "$dir/aquota.group") {
		local $stout = &supports_status($dir, "group");
		if ($stout =~ /is\s+(on|off)/) {
			# Can use output from -p mode
			if ($stout =~ /is\s+on/) {
				$rv += 2;
				}
			}
		else {
			# Fall back to testing by running quotaon
			$out = `$config{'group_quotaon_command'} $dir 2>&1`;
			if ($out =~ /Device or resource busy/i) {
				# already on..
				$rv += 2;
				}
			elsif ($out =~ /Package not installed/i) {
				# No quota support!
				return 0;
				}
			else {
				# was off.. need to turn on again
				`$config{'group_quotaoff_command'} $dir 2>&1`;
				}
			}
		}
	}
return $rv;
}

# supports_status(dir, mode)
sub supports_status
{
if (!defined($supports_status_cache{$_[0],$_[1]})) {
	local $stout = `$config{$_[1].'_quotaon_command'} -p $_[0] 2>&1`;
	$supports_status_cache{$_[0],$_[1]} =
		$stout =~ /is\s+(on|off)/ ? $stout : 0;
	}
return $supports_status_cache{$_[0],$_[1]};
}

# quotaon(filesystem, mode)
# Activate quotas and create quota files for some filesystem. The mode can
# be 1 for user only, 2 for group only or 3 for user and group
sub quotaon
{
local($out, $qf, @qfile, $flags, $version);
return if (&is_readonly_mode());

# Check which version of quota is being used
$out = `quota -V 2>&1`;
if ($out =~ /\s(\d+\.\d+)/) {
	$version = $1;
	}

# Force load of quota kernel modules
&system_logged("modprobe quota_v2 >/dev/null 2>&1");

if ($_[1]%2 == 1) {
	# turn on user quotas
	local $qf = $version >= 2 ? "aquota.user" : "quota.user";
	if (!-s "$_[0]/$qf") {
		# Setting up for the first time
		local $ok = 0;
		if (&has_command("convertquota") && $version >= 2) {
			# Try creating a quota.user file and converting it
			&open_tempfile(QUOTAFILE, ">>$_[0]/quota.user", 0, 1);
			&close_tempfile(QUOTAFILE);
			&set_ownership_permissions(undef, undef, 0600,
						   "$_[0]/quota.user");
			&system_logged("convertquota -u / 2>&1");
			$ok = 1 if (!$?);
			&unlink_file("$_[0]/quota.user");
			}
		if (!$ok) {
			# Try to create an [a]quota.user file
			&open_tempfile(QUOTAFILE, ">>$_[0]/$qf", 0, 1);
			&close_tempfile(QUOTAFILE);
			&set_ownership_permissions(undef, undef, 0600,
						   "$_[0]/$qf");
			&run_quotacheck($_[0]) || &run_quotacheck($_[0], "-u -f") || &run_quotacheck($_[0], "-u -f -m") || &run_quotacheck($_[0], "-u -f -m -c");
			}
		}
	$out = &backquote_logged("$config{'user_quotaon_command'} $_[0] 2>&1");
	if ($?) { return $out; }
	}
if ($_[1] > 1) {
	# turn on group quotas
	local $qf = $version >= 2 ? "aquota.group" : "quota.group";
	if (!-s "$_[0]/$qf") {
		# Setting up for the first time
		local $ok = 0;
		if (!$ok && &has_command("convertquota") && $version >= 2) {
			# Try creating a quota.group file and converting it
			&open_tempfile(QUOTAFILE, ">>$_[0]/quota.group", 0, 1);
			&close_tempfile(QUOTAFILE);
			&set_ownership_permissions(undef, undef, 0600,
						   "$_[0]/quota.group");
			&system_logged("convertquota -g / 2>&1");
			$ok = 1 if (!$?);
			&unlink_file("$_[0]/quota.group");
			}
		if (!$ok) {
			# Try to create an [a]quota.group file
			&open_tempfile(QUOTAFILE, ">>$_[0]/$qf", 0, 1);
			&close_tempfile(QUOTAFILE);
			&set_ownership_permissions(undef, undef, 0600,
						   "$_[0]/$qf");
			&run_quotacheck($_[0]) || &run_quotacheck($_[0], "-u -f") || &run_quotacheck($_[0], "-u -f -m") || &run_quotacheck($_[0], "-u -f -m -c");
			}
		}
	$out = &backquote_logged("$config{'group_quotaon_command'} $_[0] 2>&1");
	if ($?) { return $out; }
	}
return undef;
}

# run_quotacheck(filesys, args)
sub run_quotacheck
{
local $out =&backquote_logged("$config{'quotacheck_command'} $_[1] $_[0] 2>&1");
return $? || $out =~ /cannot remount|please stop/i ? 0 : 1;
}

# quotaoff(filesystem, mode)
# Turn off quotas for some filesystem
sub quotaoff
{
return if (&is_readonly_mode());
local($out);
if ($_[1]%2 == 1) {
	$out = &backquote_logged("$config{'user_quotaoff_command'} $_[0] 2>&1");
	if ($?) { return $out; }
	}
if ($_[1] > 1) {
	$out = &backquote_logged("$config{'group_quotaoff_command'} $_[0] 2>&1");
	if ($?) { return $out; }
	}
return undef;
}

# user_filesystems(user)
# Fills the array %filesys with details of all filesystem some user has
# quotas on
sub user_filesystems
{
return &parse_quota_output("$config{'user_quota_command'} ".quotemeta($_[0]));
}

# group_filesystems(user)
# Fills the array %filesys with details of all filesystem some group has
# quotas on
sub group_filesystems
{
return &parse_quota_output("$config{'group_quota_command'} ".quotemeta($_[0]));
}

sub parse_quota_output
{
local($n, $_, %mtab);
%mtab = &get_mtab_map();
open(QUOTA, "$_[0] 2>/dev/null |");
$n=0; while(<QUOTA>) {
	chop;
	if (/^(Disk|\s+Filesystem)/) { next; }
	if (/^(\S+)$/) {
		# Bogus wrapped line
		$filesys{$n,'filesys'} = $mtab{$1};
		local $nl = <QUOTA>;
		$nl =~/^\s+(\S+)\s+(\S+)\s+(\S+)(.{8}\s+)(\S+)\s+(\S+)\s+(\S+)(.*)/ ||
		      /^.{15}.(.{7}).(.{7}).(.{7})(.{8}.)(.{7}).(.{7}).(.{7})(.*)/;
		$filesys{$n,'ublocks'} = int($1);
		$filesys{$n,'sblocks'} = int($2);
		$filesys{$n,'hblocks'} = int($3);
		$filesys{$n,'gblocks'} = $4;
		$filesys{$n,'ufiles'} = int($5);
		$filesys{$n,'sfiles'} = int($6);
		$filesys{$n,'hfiles'} = int($7);
		$filesys{$n,'gfiles'} = $8;
		$filesys{$n,'gblocks'} = &trunc_space($filesys{$n,'gblocks'});
		$filesys{$n,'gfiles'} = &trunc_space($filesys{$n,'gfiles'});
		$n++;
		}
	elsif (/^\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)(.{8}\s+)(\S+)\s+(\S+)\s+(\S+)(.*)/ ||
	       /^(.{15}).(.{7}).(.{7}).(.{7})(.{8}.)(.{7}).(.{7}).(.{7})(.*)/) {
		# Single quota line
		$filesys{$n,'ublocks'} = int($2);
		$filesys{$n,'sblocks'} = int($3);
		$filesys{$n,'hblocks'} = int($4);
		$filesys{$n,'gblocks'} = $5;
		$filesys{$n,'ufiles'} = int($6);
		$filesys{$n,'sfiles'} = int($7);
		$filesys{$n,'hfiles'} = int($8);
		$filesys{$n,'gfiles'} = $9;
		$dev = $1; $dev =~ s/\s+$//g; $dev =~ s/^\s+//g;
		$filesys{$n,'filesys'} = $mtab{$dev};
		$filesys{$n,'gblocks'} = &trunc_space($filesys{$n,'gblocks'});
		$filesys{$n,'gfiles'} = &trunc_space($filesys{$n,'gfiles'});
		$n++;
		}
	}
close(QUOTA);
return $n;
}

# filesystem_users(filesystem)
# Fills the array %user with information about all users with quotas
# on this filesystem. This may not be all users on the system..
sub filesystem_users
{
return &parse_repquota_output(
	"$config{'user_repquota_command'} $_[0]", "user");
}

sub filesystem_groups
{
return &parse_repquota_output(
	"$config{'group_repquota_command'} $_[0]", "group");
}

sub parse_repquota_output
{
local($rep, @rep, $n, $what, $u, @uinfo);
$what = $_[1];
$$what = ( );
$rep = &backquote_command("$_[0] 2>&1");
if ($?) { return -1; }
local $st = &supports_status($_[0], $what);
if (!$st) {
	# Older system, need to build username map to identify truncation
	if ($what eq 'user') {
		setpwent();
		while(@uinfo = getpwent()) {
			$hasu{$uinfo[0]}++;
			}
		endpwent();
		}
	else {
		setgrent();
		while(@uinfo = getgrent()) {
			$hasu{$uinfo[0]}++;
			}
		endgrent();
		}
	}
@rep = split(/\n/, $rep); @rep = @rep[3..$#rep];
local $nn = 0;
local %already;
for($n=0; $n<@rep; $n++) {
	if ($rep[$n] =~ /^\s*(\S.*\S|\S)\s+[\-\+]{2}\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)(.*)/ ||
	    $rep[$n] =~ /^\s*(\S.*\S|\S)\s+[\-\+]{2}\s+(\S+)\s+(\S+)\s+(\S+)(.{7})\s+(\S+)\s+(\S+)\s+(\S+)(.*)/ ||
	    $rep[$n] =~ /([^\-\s]\S*)\s*[\-\+]{2}(.{8})(.{8})(.{8})(.{7})(.{8})(.{6})(.{6})(.*)/) {
		$$what{$nn,$what} = $1;
		$$what{$nn,'ublocks'} = int($2);
		$$what{$nn,'sblocks'} = int($3);
		$$what{$nn,'hblocks'} = int($4);
		$$what{$nn,'gblocks'} = $5;
		$$what{$nn,'ufiles'} = int($6);
		$$what{$nn,'sfiles'} = int($7);
		$$what{$nn,'hfiles'} = int($8);
		$$what{$nn,'gfiles'} = $9;
		if (!$st && $$what{$nn,$what} !~ /^\d+$/ &&
			    !$hasu{$$what{$nn,$what}}) {
			# User/group name was truncated! Try to find him..
			foreach $u (keys %hasu) {
				if (substr($u, 0, length($$what{$nn,$what})) eq
				    $$what{$nn,$what}) {
					# found him..
					$$what{$nn,$what} = $u;
					last;
					}
				}
			}
		next if ($already{$$what{$nn,$what}}++); # skip dupe users
		$$what{$nn,'gblocks'} = &trunc_space($$what{$nn,'gblocks'});
		$$what{$nn,'gfiles'} = &trunc_space($$what{$nn,'gfiles'});
		$nn++;
		}
	}
return $nn;
}

# edit_quota_file(data, filesys, sblocks, hblocks, sfiles, hfiles)
sub edit_quota_file
{
local($rv, $line, %mtab, @m, @line);
%mtab = &get_mtab_map();
@line = split(/\n/, $_[0]);
for(my $i=0; $i<@line; $i++) {
	if ($line[$i] =~ /^(\S+): blocks in use: (\d+), limits \(soft = (\d+), hard = (\d+)\)$/ && $mtab{&resolve_links("$1")} eq $_[1]) {
		# Found old-style lines to change
		$rv .= "$1: blocks in use: $2, limits (soft = $_[2], hard = $_[3])\n";
		$line[++$i] =~ /^\s*inodes in use: (\d+), limits \(soft = (\d+), hard = (\d+)\)$/;
		$rv .= "\tinodes in use: $1, limits (soft = $_[4], hard = $_[5])\n";
		}
	elsif ($line[$i] =~ /^device\s+(\S+)\s+\((\S+)\):/i && $2 eq $_[1]) {
		# Even newer-style line to change
		$rv .= "$line[$i]\n";
		$line[++$i] =~ /^used\s+(\S+),\s+limits:\s+soft=(\d+)\s+hard=(\d+)/i;
		$rv .= "Used $1, limits: soft=$_[2] hard=$_[3]\n";
		$line[++$i] =~ /^used\s+(\S+) inodes,\s+limits:\s+soft=(\d+)\s+hard=(\d+)/i;
		$rv .= "Used $1 inodes, limits: soft=$_[4] hard=$_[5]\n";
		}
	elsif ($line[$i] =~ /^\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$/ && $mtab{&resolve_links("$1")} eq $_[1]) {
		# New-style line to change
		$rv .= "  $1 $2 $_[2] $_[3] $5 $_[4] $_[5]\n";
		}
	else {
		# Leave this line alone
		$rv .= "$line[$i]\n";
		}
	}
return $rv;
}

# quotacheck(filesystem, mode(1=users, 2=group))
# Runs quotacheck on some filesystem
sub quotacheck
{
local $out;
local $cmd = $config{'quotacheck_command'};
$cmd =~ s/\s+-[ug]//g;
local $flag = $_[1] == 1 ? "-u" : $_[1] == 2 ? "-g" : "-u -g";
$out = &backquote_logged("$cmd $flag $_[0] 2>&1");
if ($?) {
	# Try with the -f and -m options
	$out = &backquote_logged("$cmd $flag -f -m $_[0] 2>&1");
	if ($?) {
		# Try with the -F option
		$out = &backquote_logged("$config{'quotacheck_command'} $flag -F $_[0] 2>&1");
		}
	return $out if ($?);
	}
return undef;
}

# copy_user_quota(user, [user]+)
# Copy the quotas for some user to many others
sub copy_user_quota
{
for($i=1; $i<@_; $i++) {
	$out = &backquote_logged("$config{'user_copy_command'} ".
				quotemeta($_[0])." ".quotemeta($_[$i])." 2>&1");
	if ($?) { return $out; }
	}
return undef;
}

# copy_group_quota(group, [group]+)
# Copy the quotas for some group to many others
sub copy_group_quota
{
for($i=1; $i<@_; $i++) {
	$out = &backquote_logged("$config{'group_copy_command'} ".
				quotemeta($_[0])." ".quotemeta($_[$i])." 2>&1");
	if ($?) { return $out; }
	}
return undef;
}

# get_user_grace(filesystem)
# Returns an array containing  btime, bunits, ftime, funits
# The units can be 0=sec, 1=min, 2=hour, 3=day
sub get_user_grace
{
return &parse_grace_output($config{'user_grace_command'}, $_[0]);
}

# get_group_grace(filesystem)
# Returns an array containing  btime, bunits, ftime, funits
# The units can be 0=sec, 1=min, 2=hour, 3=day
sub get_group_grace
{
return &parse_grace_output($config{'group_grace_command'}, $_[0]);
}

# default_grace()
# Returns 0 if grace time can be 0, 1 if zero grace means default
sub default_grace
{
return 0;
}

sub parse_grace_output
{
local(@rv, %mtab, @m);
%mtab = &get_mtab_map();
$ENV{'EDITOR'} = $ENV{'VISUAL'} = "cat";
open(GRACE, "$_[0] 2>&1 |");
while(<GRACE>) {
	if (/^(\S+): block grace period: (\d+) (\S+), file grace period: (\d+) (\S+)/ && $mtab{&resolve_links("$1")} eq $_[1]) {
		@rv = ($2, $name_to_unit{$3}, $4, $name_to_unit{$5});
		}
	elsif (/^\s+(\S+)\s+(\d+)(\S+)\s+(\d+)(\S+)/ && $mtab{&resolve_links("$1")} eq $_[1]) {
		@rv = ($2, $name_to_unit{$3}, $4, $name_to_unit{$5});
		}
	elsif (/^device\s+(\S+)\s+\((\S+)\):/i && $2 eq $_[1]) {
		if (<GRACE> =~ /^block\s+grace:\s+(\S+)\s+(\S+)\s+inode\s+grace:\s+(\S+)\s+(\S+)/i) {
			@rv = ($1, $name_to_unit{$2}, $3, $name_to_unit{$4});
			last;
			}
		}
	}
close(GRACE);
return @rv;
}

# edit_grace_file(data, filesystem, btime, bunits, ftime, funits)
sub edit_grace_file
{
local($rv, $line, @m, %mtab, @line);
%mtab = &get_mtab_map();
@line = split(/\n/, $_[0]);
for(my $i=0; $i<@line; $i++) {
	$line = $line[$i];
	if ($line =~ /^(\S+): block grace period: (\d+) (\S+), file grace period: (\d+) (\S+)/ && $mtab{&resolve_links("$1")} eq $_[1]) {
		# replace this line
		$line = "$1: block grace period: $_[2] $unit_to_name{$_[3]}, file grace period: $_[4] $unit_to_name{$_[5]}";
		}
	elsif ($line =~ /^\s+(\S+)\s+(\d+)(\S+)\s+(\d+)(\S+)/ && $mtab{&resolve_links("$1")} eq $_[1]) {
		# replace new-style line
		$line = "  $1 $_[2]$unit_to_name{$_[3]} $_[4]$unit_to_name{$_[5]}";
		}
	elsif ($line =~ /^device\s+(\S+)\s+\((\S+)\):/i && $2 eq $_[1]) {
		# replace even newer-style line
		$rv .= "$line\n";
		$line = "Block grace: $_[2] $unit_to_name{$_[3]} Inode grace: $_[4] $unit_to_name{$_[5]}";
		$i++;
		}
	$rv .= "$line\n";
	}
return $rv;
}

# grace_units()
# Returns an array of possible units for grace periods
sub grace_units
{
return ($text{'grace_seconds'}, $text{'grace_minutes'}, $text{'grace_hours'},
	$text{'grace_days'});
}

# fs_block_size(dir, device, filesystem)
# Returns the size of blocks on some filesystem, or undef if unknown.
# Consult the dumpe2fs command where possible.
sub fs_block_size
{
if ($_[2] eq "ext2" || $_[2] eq "ext3") {
	return 1024;
	# This code isn't needed, because the quota block size is
	# not the same as the filesystem block size!!
	#if (&has_command("dumpe2fs")) {
	#	local $out = `dumpe2fs -h $_[1] 2>&1`;
	#	if (!$? && $out =~ /block size:\s+(\d+)/i) {
	#		return $1;
	#		}
	#	}
	}
elsif ($_[0] eq "xfs") {
	return 1024;
	}
return undef;
}

%name_to_unit = ( "second", 0, "seconds", 0,
		  "minute", 1, "minutes", 1,
		  "hour", 2, "hours", 2,
		  "day", 3, "days", 3,
		);
foreach $k (keys %name_to_unit) {
	$unit_to_name{$name_to_unit{$k}} = $k;
	}

# Returns a hash mapping mount points to devices
sub get_mtab_map
{
local $mm = $module_info{'usermin'} ? "usermount" : "mount";
&foreign_require($mm, "$mm-lib.pl");
local ($m, %mtab);
foreach $m (&foreign_call($mm, "list_mounted", 1)) {
	if ($m->[3] =~ /loop=([^,]+)/) {
		$mtab{&resolve_links("$1")} = $m->[0];
		}
	else {
		$mtab{&resolve_links($m->[1])} = $m->[0];
		}
	}
return %mtab;
}

1;

