#!/usr/bin/perl

use strict;
use warnings;
use File::Path;
use JSON;
use Getopt::Long qw(GetOptions);
use Scalar::Util qw(looks_like_number);

my $usage = <<EOT;
Uso: $0 <archivo_json> [OPTIONS]
Opciones:
-s -schema muestra la estructura del archivo json
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
    'schema|s',
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

# ================= Filtro de caracteres codificados en latin1 =================
my %encoding_rpl =( i => '\\\udced', e => '\\\udce9', o => '\\\udcf3');
for my $enc (keys %encoding_rpl){
    $file_content =~ s/$encoding_rpl{$enc}/$enc/g if $file_content =~ /$encoding_rpl{$enc}/;
}
# ==============================================================================

# Buscamos la cosa
my $data = $json->decode($file_content);

my %type = (
    'JSON::PP::Boolean' => 'Boolean',
    'HASH'              => 'Hash',
    'ARRAY'             => 'Array',
    ''                  => 'String' #String or Numbers
);

#FIXME: random host selection may choose one with an empty array.
#       This won't print the structure of the elements it may contain.
if ($opt{schema} || !$opt{node}) {
    print "HOST\n";
    my $random_host = (keys %$data)[0];
    schema($data->{ $random_host });
    exit;
}
elsif (!$opt{key}) {
    print "HOST->$opt{node}\n";
    my $random_host = (keys %$data)[0];

    schema( get_node($data->{ $random_host },$opt{node}) );
    exit;
}

my $filtered = {};
my %resumen_total = ();

for my $host (keys %$data){

    #FIXME: support for a multi-level node definition
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

# Navigate through the json data received,
# printing the nested structure with data types
sub schema {
    my $data = shift;
    my $level = shift // 0;
    my $tab = '|   ';
    $level++;
    if ($type{ref $data} eq 'Hash') {
        foreach my $node (sort keys %$data ){
            my $node_type = $type{ref $data->{$node}};
            printf '%s%s: %s'.$/, ($tab x $level), $node, $node_type;
            schema($data->{$node},$level)
                unless $node_type eq 'String' || $node_type eq 'Boolean';
        }
    }
    elsif ($type{ref $data} eq 'Array') {
        my $p = 0;
        my $node = $data->[$p];
        my $node_type = $type{ref $node };
        printf '%s[%s]: %s'.$/, ($tab x $level), $p, $node_type;
        #FIXME: $node_type is 'String' when array is empty
        schema($node,$level)
            unless $node_type eq 'String' || $node_type eq 'Boolean';
    }

}

sub get_node{
    my $host = shift;
    my $nodes_str = shift;

    my @nodes = split /,/,$nodes_str;
    my $selected;

    if(@nodes == 1){
        $selected = $host->{$nodes[0]};
    }else{
        my $start_node = shift @nodes;
        # We know by the structure, that the first node is never an array
        $selected = $host->{$start_node};
        # Using while to be able to check ahead later, and maybe guess if things are going sour
        #REVIEW: check performance when travelling a full list of hosts
        while (@nodes){
            my $node = shift @nodes;
            #REVIEW: Should I check before if the requested item exists?
            if ($node =~ /\[(\d+)\]/){
                $selected = $selected->[$1];
            }else{
                $selected = $selected->{$node};
            }
        }
    }
    return $selected;
}
