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

package MongoDB::DeleteResult;

# ABSTRACT: MongoDB deletion result object

use version;
our $VERSION = 'v0.999.998.7'; # TRIAL

use Moose;
use MongoDB::_Types -types;
use Types::Standard -types;
use namespace::clean -except => 'meta';

with 'MongoDB::Role::_WriteResult';

=attr acknowledged

Indicates whether this write result was ackowledged. If not, then all other
members of this result will be zero or undefined.

=cut

=attr deleted_count

The number of documents that matched the filter.

=cut

has deleted_count => (
    is      => 'ro',
    isa     => Num,
    default => 0,
);

__PACKAGE__->meta->make_immutable;

1;

=method assert

Throws an error if write errors or write concern errors occurred.

=cut

=method assert_no_write_error

Throws a MongoDB::WriteError if C<count_write_errors> is non-zero; otherwise
returns 1.

=cut

=method assert_no_write_concern_error

Throws a MongoDB::WriteConcernError if C<count_write_concern_errors> is non-zero; otherwise
returns 1.

=cut


__END__

=head1 SYNOPSIS

    my $result = $coll->delete( { _id => $oid } );

    if ( $result->acknowledged ) {
        ...
    }

=head1 DESCRIPTION

This class encapsulates the results from a deletion operation.

=cut
