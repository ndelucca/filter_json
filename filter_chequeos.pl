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

-r -render define la estructura que se desea mostrar (default: full)
  full:     se muestra todos los datos del host
  short:    se muestra solo la estructura definida en -n
  <node chain>  se muestra una estructura segun patron ingresado, con mismo formato que -n

-f -filter filtro a aplicar. Si el filtro tiene argumentos, separarlos con ,

Filtros disponibles (default: notnull)
    notnull: nodos con contenido distinto de null    Uso: -f notnull
    null:    nodos sin contenido o contenido null    Uso: -f null
    gt|ngt:  valor del nodo mayor a <val>.           Uso: -f gt,<string> | -f ngt,<number>
    ge|nge:  valor del nodo mayor o igual a <val>    Uso: -f ge,<string> | -f nge,<number>
    lt|nlt:  valor del nodo menor a <val>            Uso: -f lt,<string> | -f nlt,<number>
    le|nle:  valor del nodo menor o igual a <val>    Uso: -f le,<string> | -f nle,<number>
    eq|neq:  valor del nodo igual a <val>            Uso: -f eq,<string> | -f neq,<number>
    ne|nne:  valor del nodo distinto a <val>         Uso: -f ne,<string> | -f nne,<number>

EOT

my %opt = (
    render => 'full',
    node => '',
    filter => 'notnull',
);
GetOptions (
    \%opt,
    'help|h',
    'schema|s',
    'node|n=s',
    'render|r=s',
    'filter|f=s',
    'total|t',
) or die $usage;

my $filename = shift @ARGV or die "Debe indicar un archivo";

die $usage if $opt{help};

# Traigo el reporte
open my $fh, '<', $filename or die "No puede abrirse el archivo json. $!";
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

# Definition of variable types in the structure
my %type = (
    #REVIEW: $json->is_pp is true, use JSON::is_bool($scalar)
    'JSON::PP::Boolean' => 'boolean',
    'HASH'              => 'hash',
    'ARRAY'             => 'array',
    ''                  => 'string' #String or Numbers
);

get_schema($data) if ( $opt{schema} || !$opt{node} );

my $filtered = {};
my %resumen_total = ();

my $filters = {
    gt      => sub { return $_[0] gt $_[1]  },
    ge      => sub { return $_[0] ge $_[1]  },
    lt      => sub { return $_[0] lt $_[1]  },
    le      => sub { return $_[0] le $_[1]  },
    eq      => sub { return $_[0] eq $_[1]  },
    ne      => sub { return $_[0] ne $_[1]  },
    ngt     => sub { return $_[0] >  $_[1]  },
    nge     => sub { return $_[0] >= $_[1]  },
    nlt     => sub { return $_[0] <  $_[1]  },
    nle     => sub { return $_[0] <= $_[1]  },
    neq     => sub { return $_[0] == $_[1]  },
    nne     => sub { return $_[0] != $_[1]  },
    #A JSON null atom becomes undef in Perl
    null    => sub { return ! defined $_[0] },
    notnull => sub { return defined   $_[0] }
};

for my $host (keys %$data){

    my $item = get_node( $data->{$host}, $opt{node} );
    my $item_render = render_node( $data->{$host}, $opt{node} , $opt{render} );

    $filtered->{$host} = $item_render if filter( $item, $opt{filter} );

    #REVIEW: check condition for calling this subroutine
    # Keep in mind that we probably need to work with $filtered->{$host} from now on
    # add_to_total($filtered->{$host}) if type_hash($item_render);

}

print $json->utf8->pretty(1)->encode($filtered);
exit;

# =================== TODO AGGREGATE DATA================================

# sub add_to_total{
#     my $hashref = shift;

#     for my $i (keys %{$hashref}){
#         $resumen_total{$i} += $hashref->{$i} if looks_like_number($hashref->{$i});
#     }
#     return;
# }

# ==================== Schema management =======================

sub get_schema {

    my $data = shift;
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

# =================== Search engine ====================

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

# ========== Display and render management =============

sub render_node{
    my $host_data = shift;
    my $nodes_str = shift;
    my $opt = shift;

    my %render_options = (
        full        => sub { return get_node( $host_data ) },
        short       => sub { return get_node( $host_data, $nodes_str ) },
        node_chain  => sub { return get_node( $host_data, $opt ) }, # Maybe needs input filtering
    );

    my $render = $render_options{$opt} || $render_options{node_chain};
    return $render->();

}

# ================ Filter management =====================

sub filter{
    my $item = shift;
    my $opt = shift;

    my @filter_opt = split /,/,$opt;
    my $filter_name = shift @filter_opt;

    my $filter = $filters->{ $filter_name } || die "Operacion $filters->{$filter_name} desconocida";

    return $filter->( $item, @filter_opt );
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
