#
#  Copyright 2014 MongoDB, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

package MongoDB::Op::_BatchInsert;

# Encapsulate a multi-document insert operation; returns a
# MongoDB::InsertManyResult

use version;
our $VERSION = 'v0.999.998.7'; # TRIAL

use Moose;

use MongoDB::BSON;
use MongoDB::Error;
use MongoDB::InsertManyResult;
use MongoDB::OID;
use MongoDB::_Protocol;
use MongoDB::_Types -types;
use Types::Standard -types;
use Safe::Isa;
use Scalar::Util qw/blessed reftype/;
use Tie::IxHash;
use namespace::clean -except => 'meta';

has db_name => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has coll_name => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

# may or may not have _id; will be added if check_keys is true
has documents => (
    is       => 'ro',
    isa      => ArrayRef,
    required => 1,
);

has ordered => (
    is      => 'ro',
    isa     => Bool,
    default => 1,
);

has check_keys => (
    is      => 'ro',
    isa     => Bool,
    default => 1,
);

has _doc_ids => (
    is      => 'ro',
    isa     => ArrayRef,
    writer  => '_set_doc_ids',
);

with qw/MongoDB::Role::_WriteOp/;

sub BUILD {
    my ($self) = @_;

    # coerce documents to IxHash or die trying
    # XXX eventually, do this with a Types::Standard coercion?
    for my $d ( @{ $self->documents } ) {
        if ( $d->$_isa('Tie::IxHash') ) {
            next;
        }
        elsif ( ref($d) eq 'ARRAY' ) {
            $d = Tie::IxHash->new(@$d);
        }
        elsif ( ref($d) eq 'HASH' ) {
            $d = Tie::IxHash->new(%$d);
        }
        elsif ( blessed($d) && reftype($d) eq 'HASH' ) {
            $d = Tie::IxHash->new(%$d);
        }
        else {
            MongoDB::DocumentError->throw(
                message  => "Can't insert document of type " . ref($d),
                document => $d,
            );
        }
    }

    return;
}

sub execute {
    my ( $self, $link ) = @_;

    # XXX until we have a proper BSON::Raw class, we bless on the fly
    my $max_size = $link->max_bson_object_size;
    my $check_keys = $self->check_keys;

    my $opts = {
        invalid_chars => $check_keys ? '.' : '',
        max_length => $max_size,
    };

    my @ids;

    my $insert_docs = [
        map {
            my $local_opts = { %$opts };
            if ( $check_keys ) {
                my $id = $_->FETCH('_id') || MongoDB::OID->new;
                push @ids, $id;
                $local_opts->{first_key} = '_id';
                $local_opts->{first_value} = $id;
            }
            else {
                push @ids, undef;
            }
            my $s = $self->bson_codec->encode_one( $_, $local_opts );
            bless \$s, "MongoDB::BSON::Raw";
        } @{ $self->documents }
    ];

    $self->_set_doc_ids(\@ids);

    my $res =
        $link->accepts_wire_version(2)
      ? $self->_command_insert( $link, $insert_docs )
      : $self->_legacy_op_insert( $link, $insert_docs );

    $res->assert;
    return $res;
}

sub _command_insert {
    my ( $self, $link, $insert_docs ) = @_;

    # XXX have to check size of docs to insert here and possibly split it

    my $cmd = Tie::IxHash->new(
        insert       => $self->coll_name,
        documents    => $insert_docs,
        writeConcern => $self->write_concern->as_struct,
    );

    return $self->_send_write_command( $link, $cmd, undef, "MongoDB::InsertManyResult" );
}

sub _legacy_op_insert {
    my ( $self, $link, $insert_docs ) = @_;

    # XXX have to check size of docs to insert here and possibly split it

    my $ns = $self->db_name . "." . $self->coll_name;
    my $op_bson =
      MongoDB::_Protocol::write_insert( $ns, join( "", map { $$_ } @$insert_docs ) );

    return $self->_send_legacy_op_with_gle( $link, $op_bson, undef,
        "MongoDB::InsertManyResult" );
}

sub _parse_cmd {
    my ( $self, $res ) = @_;
    return unless $res->{ok};
    my $inserted = $self->_doc_ids;
    my $ids = [ map +{ index => $_,  _id => $inserted->[$_] }, 0 .. $#{$inserted} ];
    return ( inserted_count => scalar @$inserted, inserted => $ids );
}

BEGIN {
    no warnings 'once';
    *_parse_gle = \&_parse_cmd;
}

1;
