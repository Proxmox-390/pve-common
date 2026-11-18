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

# /proc/net/route tests

my $route_header =
    "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n";

my $net_route = {
    little => $route_header
        . "vmbr0\t00000000\t016433C6\t0003\t0\t0\t0\t00000000\t0\t0\t0\n"
        . "vmbr0\t006433C6\t00000000\t0001\t0\t0\t0\t00FFFFFF\t0\t0\t0\n"
        . "enc10\t007100CB\t00000000\t0001\t0\t0\t100\t00FFFFFF\t1500\t0\t0\n",
    big => $route_header
        . "vmbr0\t00000000\tC6336401\t0003\t0\t0\t0\t00000000\t0\t0\t0\n"
        . "vmbr0\tC6336400\t00000000\t0001\t0\t0\t0\tFFFFFF00\t0\t0\t0\n"
        . "enc10\tCB007100\t00000000\t0001\t0\t0\t100\tFFFFFF00\t1500\t0\t0\n",
};

my $expected_routes = [
    {
        iface => 'vmbr0',
        dest => '0.0.0.0',
        gateway => '198.51.100.1',
        mask => '0.0.0.0',
        metric => 0,
        mtu => 0,
    },
    {
        iface => 'vmbr0',
        dest => '198.51.100.0',
        gateway => '0.0.0.0',
        mask => '255.255.255.0',
        metric => 0,
        mtu => 0,
    },
    {
        iface => 'enc10',
        dest => '203.0.113.0',
        gateway => '0.0.0.0',
        mask => '255.255.255.0',
        metric => 100,
        mtu => 1500,
    },
];

my $proc_net_route;
my $io_file_module = Test::MockModule->new('IO::File');
$io_file_module->mock(
    new => sub {
        my ($class, $filename, @args) = @_;
        return $io_file_module->original('new')->($class, $filename, @args)
            if ($filename // '') ne '/proc/net/route';
        open(my $fh, '<', \$proc_net_route) or die "open in-memory file failed - $!\n";
        return $fh;
    },
);

subtest 'test read_proc_net_route parser' => sub {
    # /proc/net/route prints each address as a host-endian integer
    my $host_endian = unpack('C', pack('L', 1)) == 1 ? 'little' : 'big';

    for my $endian (sort keys %$net_route) {
        SKIP: {
            skip "/proc/net/route of a $endian-endian host, this host is $host_endian-endian", 1
                if $endian ne $host_endian;

            $proc_net_route = $net_route->{$endian};
            my $res = PVE::ProcFSTools::read_proc_net_route();
            is_deeply($res, $expected_routes,
                "parsed /proc/net/route of a $endian-endian host");
        }
    }
};

done_testing();
