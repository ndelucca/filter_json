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

-n -node   cadena de nodos donde buscar separados con ,
           indicando key de hash o [0] para un array

-r -render define la estructura que se desea mostrar. permite:
  full:     se muestra todos los datos del host
  short:    se muestra solo el resumen final, sin datos por host
  node:     se muestra solo la estructura definida en -n
  <node chain>  se muestra una estructura segun patron ingresado, con mismo formato que -n

Filtros:
Por default, si no se indica ningun filtro, se filtran los items vacios

-o -oper   operacion a evaluar. Por ej. ">" "eq" "=="
-v -value  valor umbral a evaluar. solo se usa en conjunto con -o

EOT

my %opt = (
    render => 'full',
    node => ''
);
GetOptions (
    \%opt,
    'help|h',
    'schema|s',
    'node|n=s',
    'render|r=s',
    'oper|o=s',
    'value|v=i',
    'total|t',
) or die $usage;

my $filename = shift @ARGV or die "Debe indicar un archivo";

die $usage if $opt{help};

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
my $json = JSON->new();
my $data = $json->decode($file_content);

my %type = (
    'JSON::PP::Boolean' => 'boolean',
    'HASH'              => 'hash',
    'ARRAY'             => 'array',
    ''                  => 'string' #String or Numbers
);

if ( $opt{schema} || !$opt{node} ) {
    #FIXME: random host selection may choose one with an empty array.
    #       This won't print the structure of the elements it may contain.
    my $random_host = (keys %$data)[0];

    my $title = 'host';
    my $search = $data->{ $random_host };

    if($opt{node}){
        $title.= $_ for map { $_ =~ /\[(\d+)\]/ ? "->[$1]" : "->{$_}" }
                        split /,/,$opt{node};
        $search = get_node($data->{ $random_host },$opt{node});
    }

    print "$title\n";
    schema( $search );
    exit;
}

my $filtered = {};
my %resumen_total = ();

for my $host (keys %$data){

    my $item = get_node( $data->{$host}, $opt{node} );
    my $item_render = render_node( $data->{$host}, $opt{node} , $opt{render} );

    if ( $item ){
        if (!$opt{oper}){
            #FIXME: fails if $item is an array or string
            $filtered->{$host} = $item_render if %{$item};
        }else{
            $filtered->{$host} = $item_render if eval "$item $opt{oper} $opt{value}";
        }

        #REVIEW: check condition for calling this subroutine
        add_to_total($filtered->{$host}) if type_hash($item_render);
    }
}

# Output
if($opt{render} eq 'short'){
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
    return;
}

# Navigate through the json data received,
# printing the nested structure with data types
sub schema {
    my $data = shift;
    my $level = shift // 0;
    my $tab = '|   ';
    $level++;
    if ( type_hash($data) ) {
        foreach my $node (sort keys %$data ){
            my $inode = $data->{$node};
            printf '%s%s: %s'.$/, ($tab x $level), $node, ucfirst get_type($inode);
            schema($inode,$level)
                unless type_string($inode) || type_bool($inode);
        }
    }
    elsif ( type_array($data) ) {
        my $p = 0;
        my $inode = $data->[$p];
        printf '%s[%s]: %s'.$/, ($tab x $level), $p, ucfirst get_type($inode);
        #FIXME: inode type is 'String' when array is empty!
        schema($inode,$level)
            unless type_string($inode) || type_bool($inode);
    }
    else {
        print ucfirst get_type($data) if $level == 1;
    }
    return;
}

sub get_node{
    my $host = shift;
    my $nodes_str = shift;

    return $host unless $nodes_str;

    #REVIEW: check performance when travelling a full list of hosts
    #        define arrayref outside get_node and access elements by index
    my @nodes = split /,/,$nodes_str;

    return $host->{$nodes[0]} if @nodes == 1;

    # We know by the structure, that the first node is never an array
    my $start_node = shift @nodes;

    my $selected = $host->{$start_node};
    # Using while to be able to check ahead later, and maybe guess if things are going sour
    while (@nodes){
        my $node = shift @nodes;
        #REVIEW: Should I check before if the requested item exists?
        if ($node =~ /\[(\d+)\]/){
            $selected = $selected->[$1];
        }else{
            $selected = $selected->{$node};
        }
    }

    return $selected;
}

sub render_node{
    my $host_data = shift;
    my $nodes_str = shift;
    my $opt = shift;

    my %render = (
        full        => sub { return get_node( $host_data ) },
        short       => sub { return get_node( $host_data, $nodes_str ) },
        node        => sub { return get_node( $host_data, $nodes_str ) },
        node_chain  => sub { return get_node( $host_data, $opt ) }, # Maybe needs input filtering
    );

    return $render{$opt}->() if $render{$opt};

    return $render{node_chain}->();

}

# ================= Types management =====================

sub type_hash   { return get_type($_[0]) eq 'hash'    }
sub type_array  { return get_type($_[0]) eq 'array'   }
sub type_string { return get_type($_[0]) eq 'string'  }
sub type_number { return get_type($_[0]) eq 'number'  }
sub type_bool   { return get_type($_[0]) eq 'boolean' }

sub get_type {
    my $node = shift;
    return 'undefined' unless defined $node;
    my $type = $type{ref $node};
    return 'number' if $type eq 'string' && $node =~ /^\d+(?:\.\d+)?$/;
    return $type;
}
