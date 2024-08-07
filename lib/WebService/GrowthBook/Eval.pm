package WebService::GrowthBook::Eval;
use strict;
use warnings;
no indirect;
use Exporter 'import';
use Scalar::Util qw(looks_like_number);
our @EXPORT_OK = qw(eval_condition);

sub eval_condition {
    my ($attributes, $condition) = @_;

    if (exists $condition->{"\$or"}) {
        return eval_or($attributes, $condition->{"\$or"});
    }
    if (exists $condition->{"\$nor"}) {
        return !eval_or($attributes, $condition->{"\$nor"});
    }
    if (exists $condition->{"\$and"}) {
        return eval_and($attributes, $condition->{"\$and"});
    }
    if (exists $condition->{"\$not"}) {
        return !eval_condition($attributes, $condition->{"\$not"});
    }

    while (my ($key, $value) = each %$condition) {
        if (!eval_condition_value($value, get_path($attributes, $key))) {
            return 0;
        }
    }

    return 1;
}

sub get_path {
    my ($attributes, $path) = @_;
    my $current = $attributes;

    foreach my $segment (split /\./, $path) {
        if (ref($current) eq 'HASH' && exists $current->{$segment}) {
            $current = $current->{$segment};
        } else {
            return undef;
        }
    }
    return $current;
}

sub eval_or {
    my ($attributes, $conditions) = @_;

    if (scalar @$conditions == 0) {
        return 1;  # True
    }

    foreach my $condition (@$conditions) {
        if (eval_condition($attributes, $condition)) {
            return 1;  # True
        }
    }
    return 0;  # False
}
sub eval_and {
    my ($attributes, $conditions) = @_;

    foreach my $condition (@$conditions) {
        if (!eval_condition($attributes, $condition)) {
            return 0;  # False
        }
    }
    return 1;  # True
}

# TODO turn 1 and 0 to json true and false

sub eval_condition_value {
    my ($condition_value, $attribute_value) = @_;

    if (ref($condition_value) eq 'HASH' && is_operator_object($condition_value)) {
        while (my ($key, $value) = each %$condition_value) {
            if (!eval_operator_condition($key, $attribute_value, $value)) {
                return 0;  # False
            }
        }
        return 1;  # True
    }
    # TODO check this is str or number or what else
    return $condition_value eq $attribute_value;
}

sub is_operator_object {
    my ($obj) = @_;

    foreach my $key (keys %$obj) {
        if (substr($key, 0, 1) ne '$') {
            return 0;  # False
        }
    }
    return 1;  # True
}

sub compare {
    my ($a, $b) = @_;
    if(!defined ($a)){
        $a = 0;
    }
    if(!defined ($b)){
        $b = 0;
    }
    return $a <=> $b;
}
sub eval_operator_condition {
    my ($operator, $attribute_value, $condition_value) = @_;

    if ($operator eq '$eq') {
        eval {
            return compare($attribute_value, $condition_value) == 0;
        } or return 0;
    } elsif ($operator eq '$ne') {
        eval {
            return compare($attribute_value, $condition_value) != 0;
        } or return 0;
    } elsif ($operator eq '$lt') {
        eval {
            return compare($attribute_value, $condition_value) < 0;
        } or return 0;
    } elsif ($operator eq '$lte') {
        eval {
            return compare($attribute_value, $condition_value) <= 0;
        } or return 0;
    } elsif ($operator eq '$gt') {
        eval {
            return compare($attribute_value, $condition_value) > 0;
        } or return 0;
    } elsif ($operator eq '$gte') {
        eval {
            return compare($attribute_value, $condition_value) >= 0;
        } or return 0;
    } elsif ($operator eq '$veq') {
        return padded_version_string($attribute_value) eq padded_version_string($condition_value);
    } elsif ($operator eq '$vne') {
        return padded_version_string($attribute_value) ne padded_version_string($condition_value);
    } elsif ($operator eq '$vlt') {
        return padded_version_string($attribute_value) lt padded_version_string($condition_value);
    } elsif ($operator eq '$vlte') {
        return padded_version_string($attribute_value) le padded_version_string($condition_value);
    } elsif ($operator eq '$vgt') {
        return padded_version_string($attribute_value) gt padded_version_string($condition_value);
    } elsif ($operator eq '$vgte') {
        return padded_version_string($attribute_value) ge padded_version_string($condition_value);
    } elsif ($operator eq '$regex') {
        eval {
            my $r = qr/$condition_value/;
            return $attribute_value =~ $r;
        } or return 0;
    } elsif ($operator eq '$in') {
        return 0 unless ref($condition_value) eq 'ARRAY';
        return is_in($condition_value, $attribute_value);
    } elsif ($operator eq '$nin') {
        return 0 unless ref($condition_value) eq 'ARRAY';
        return !is_in($condition_value, $attribute_value);
    } elsif ($operator eq '$elemMatch') {
        return elem_match($condition_value, $attribute_value);
    } elsif ($operator eq '$size') {
        return 0 unless ref($attribute_value) eq 'ARRAY';
        return eval_condition_value($condition_value, scalar @$attribute_value);
    } elsif ($operator eq '$all') {
        return 0 unless ref($attribute_value) eq 'ARRAY';
        foreach my $cond (@$condition_value) {
            my $passing = 0;
            foreach my $attr (@$attribute_value) {
                if (eval_condition_value($cond, $attr)) {
                    $passing = 1;
                    last;
                }
            }
            return 0 unless $passing;
        }
        return 1;
    } elsif ($operator eq '$exists') {
        return !$condition_value ? !defined $attribute_value : defined $attribute_value;
    } elsif ($operator eq '$type') {
        return get_type($attribute_value) eq $condition_value;
    } elsif ($operator eq '$not') {
        return !eval_condition_value($condition_value, $attribute_value);
    }
    return 0;
}


sub padded_version_string {
    my ($input) = @_;

    # If input is a number, convert to a string
    if (looks_like_number($input)) {
        $input = "$input";
    }

    if (!defined $input || ref($input) || $input eq '') {
        $input = "0";
    }

    # Remove build info and leading `v` if any
    $input =~ s/^v|\+.*$//g;

    # Split version into parts (both core version numbers and pre-release tags)
    my @parts = split(/[-.]/, $input);

    # If it's SemVer without a pre-release, add `~` to the end
    if (scalar(@parts) == 3) {
        push @parts, "~";
    }

    # Left pad each numeric part with spaces so string comparisons will work ("9">"10", but " 9"<"10")
    @parts = map { /^\d+$/ ? sprintf("%5s", $_) : $_ } @parts;

    # Join back together into a single string
    return join("-", @parts);
}
sub is_in {
    my ($condition_value, $attribute_value) = @_;

    if (ref($attribute_value) eq 'ARRAY') {
        my %condition_hash = map { $_ => 1 } @$condition_value;
        foreach my $item (@$attribute_value) {
            return 1 if exists $condition_hash{$item};
        }
        return 0;
    }
    return grep { $_ eq $attribute_value } @$condition_value;
}

sub elem_match {
    my ($condition, $attribute_value) = @_;

    # Check if $attribute_value is an array reference
    return 0 unless ref($attribute_value) eq 'ARRAY';

    foreach my $item (@$attribute_value) {
        if (is_operator_object($condition)) {
            if (eval_condition_value($condition, $item)) {
                return 1;
            }
        } else {
            if (eval_condition($item, $condition)) {
                return 1;
            }
        }
    }

    return 0;
}

sub get_type {
    my ($attribute_value) = @_;

    if (!defined $attribute_value) {
        return "null";
    }
    if (ref($attribute_value) eq '') {
        if ($attribute_value =~ /^[+-]?\d+$/ || $attribute_value =~ /^[+-]?\d*\.\d+$/) {
            return "number";
        }
        if ($attribute_value eq '0' || $attribute_value eq '1') {
            return "boolean";
        }
        return "string";
    }
    if (ref($attribute_value) eq 'ARRAY' || ref($attribute_value) eq 'HASH') {
        return "array";
    }
    if (ref($attribute_value) eq 'HASH') {
        return "object";
    }
    if (ref($attribute_value) eq 'SCALAR' && ($$attribute_value eq '0' || $$attribute_value eq '1')) {
        return "boolean";
    }
    return "unknown";
}

1;