#!/usr/bin/perl

use strict;
use warnings;

use lib '../src';

use Test::More;
use Test::MockModule;

use PVE::Tools;
use PVE::ProcFSTools;

# the proc "state"
my $proc = {
    version => '',
};

my $pve_common_tools;
$pve_common_tools = Test::MockModule->new('PVE::File');
$pve_common_tools->mock(
    file_read_first_line => sub {
        my ($filename) = @_;

        $filename =~ s!^/proc/!!;

        my $res = $proc->{$filename};

        if (ref($res) eq 'CODE') {
            $res = $res->();
        }

        chomp $res;
        return $res;
    },
);

# version tests

my @kernel_versions = (
    {
        version =>
            'Linux version 5.3.10-1-pve (build@pve) (gcc version 8.3.0 (Debian 8.3.0-6)) #1 SMP PVE 5.3.10-1 (Thu, 14 Nov 2019 10:43:13 +0100)',
        expect => [5, 3, 10, '1-pve', '5.3.10-1-pve'],
    },
    {
        version =>
            'Linux version 5.0.21-5-pve (build@pve) (gcc version 8.3.0 (Debian 8.3.0-6)) #1 SMP PVE 5.0.21-10 (Wed, 13 Nov 2019 08:27:10 +0100)',
        expect => [5, 0, 21, '5-pve', '5.0.21-5-pve'],
    },
    {
        version =>
            'Linux version 5.0.21+ (build@pve) (gcc version 8.3.0 (Debian 8.3.0-6)) #27 SMP Tue Nov 12 10:30:36 CET 2019',
        expect => [5, 0, 21, '+', '5.0.21+'],
    },
    {
        version =>
            'Linu$ version 2 (build@pve) (gcc version 8.3.0 (Debian 8.3.0-6)) #27 SMP Tue Nov 12 10:30:36 CET 2019',
        expect => [0, 0, 0, '', ''],
    },
);

subtest 'test kernel_version parser' => sub {
    for my $test (@kernel_versions) {
        $proc->{version} = $test->{version};

        my $res = [PVE::ProcFSTools::kernel_version()];

        is_deeply($res, $test->{expect}, "got version <" . $res->[4] . "> same as expected");
    }
};

# cpuinfo tests, fixtures in cpuinfo/

my $cpuinfo_tests = {
    'x86_64-2-socket' => {
        vendor => 'GenuineIntel',
        family => 6,
        model => 'Intel(R) Xeon(R) Gold 6130 CPU @ 2.10GHz',
        mhz => '2100.000',
        cpus => 4,
        sockets => 2,
        cores => 4,
        hvm => 1,
    },
    'aarch64-neoverse-n1' => {
        vendor => 'ARM',
        family => 0,
        model => 'Neoverse-N1',
        mhz => 0,
        cpus => 4,
        sockets => 1,
        cores => 1,
        hvm => '',
    },
};

subtest 'test cpuinfo parser' => sub {
    for my $name (sort keys %$cpuinfo_tests) {
        open(my $fh, '<', "cpuinfo/$name") or die "unable to open cpuinfo/$name - $!\n";
        my $res = PVE::ProcFSTools::parse_cpuinfo($fh);
        close($fh);

        my $expect = $cpuinfo_tests->{$name};
        my $got = { map { $_ => $res->{$_} } keys %$expect };
        is_deeply($got, $expect, "parsed cpuinfo of $name");
    }

    my $res = PVE::ProcFSTools::parse_cpuinfo(undef);
    is($res->{model}, 'unknown', 'no cpuinfo results in defaults');
};

done_testing();
