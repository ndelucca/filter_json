#!/usr/bin/perl

use strict;
use warnings;
use File::Path;
use JSON;
use Getopt::Long qw(GetOptions);
use Scalar::Util qw(looks_like_number);

my $usage = <<EOT;
Uso: $0 <nombre_archivo> [OPTIONS]
Opciones:
-k -key    key o propiedad a buscar
-n -node   key interno donde buscar

-t -total  solo muestra el resumen total de datos
Filtros:
Por default, si no se indica ningun filtro, se filtran los items vacios

-o -oper   operacion a evaluar. Por ej. ">" "eq" "=="
-v -value  valor umbral a evaluar. solo se usa en conjunto con -o

EOT

my %opt = ();
GetOptions (
    \%opt,
    'help|h',
    'node|n=s',
    'key|k=s',
    'oper|o=s',
    'value|v=i',
    'total|t',
) or die $usage;

my $filename = shift @ARGV or die "Debe indicar un archivo";

die $usage if $opt{help};

my $json = JSON->new();

# Traigo el reporte
open my $fh, '<', $filename or die "No puede abrirse el archivo json";
read $fh, my $file_content, -s $fh;
close $fh;

# Buscamos la cosa
my $data = $json->decode($file_content);

# ================= Filtro de caracteres codificados en latin1 =================
my %encoding_rpl =( i => '\\\udced', e => '\\\udce9', o => '\\\udcf3');
for my $enc (keys %encoding_rpl){
    $file_content =~ s/$encoding_rpl{$enc}/$enc/g if $file_content =~ /$encoding_rpl{$enc}/;
}
# ==============================================================================

my %type = (
    'JSON::PP::Boolean' => 'Boolean',
    'HASH'              => 'Hash',
    ''                  => 'String' #???
);

if (!$opt{node}) {
    #print 'Available nodes (-n -node): ', join ', ', sort keys %{ $data->{ (keys %$data)[0] } };
    my $some_host = $data->{ (keys %$data)[0] };
    print "Available nodes (-n -node):\n";
    foreach my $node (sort keys %$some_host ){
        printf '* %s: %s'.$/, $node, $type{ref $some_host->{$node} };
    }
    exit 0;
}

if (!$opt{key}) {
    my $some_host = $data->{ (keys %$data)[0] };
    my $node = $some_host->{$opt{node}};
    print "Available keys on node (-k -key):\n";
    foreach my $key (sort keys %$node ){
        printf '* %s: %s'.$/, $key, $type{ref $node->{$key} };
    }
    exit 0;
}


my $filtered = {};
my %resumen_total = ();

for my $host (keys %$data){

    my $item = $data->{$host}->{$opt{node}}->{$opt{key}};

    if ( $item ){
        if (!$opt{oper}){
            $filtered->{$host} = $item if $type{ref $item} eq 'String';
            $filtered->{$host} = $item->{resumen} if $type{ref $item} eq 'Hash' && %{$item};
        }else{
            $filtered->{$host} = $item->{resumen} if eval "$item $opt{oper} $opt{value}";
        }

        add_to_total($filtered->{$host}) if $type{ref $item} ne 'String';
    }
}

# Output
if($opt{total}){
    print $json->utf8->pretty(1)->encode(\%resumen_total);
}else{
    $filtered->{resumen_total} = \%resumen_total;
    print $json->utf8->pretty(1)->encode($filtered);
}

sub add_to_total{

    my $hashref = shift;

    for my $i (keys %{$hashref}){
        $resumen_total{$i} += $hashref->{$i} if looks_like_number($hashref->{$i});
    }

}
