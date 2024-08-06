package WebService::GrowthBook;
# ABSTRACT: ...

use strict;
use warnings;
no indirect;
use feature qw(state);
use Object::Pad;
use JSON::MaybeUTF8 qw(decode_json_text);
use Scalar::Util qw(blessed);
use Log::Any qw($log);
use WebService::GrowthBook::FeatureRepository;
use WebService::GrowthBook::Feature;
use WebService::GrowthBook::FeatureResult;
use WebService::GrowthBook::InMemoryFeatureCache;

our $VERSION = '0.003';

=head1 NAME

WebService::GrowthBook - sdk of growthbook

=head1 SYNOPSIS

    use WebService::GrowthBook;
    my $instance = WebService::GrowthBook->new(client_key => 'my key');
    $instance->load_features;
    if($instance->is_on('feature_name')){
        # do something
    }
    else {
        # do something else
    }
    my $string_feature = $instance->get_feature_value('string_feature');
    my $number_feature = $instance->get_feature_value('number_feature');
    # get decoded json
    my $json_feature = $instance->get_feature_value('json_feature');

=head1 DESCRIPTION

    This module is a sdk of growthbook, it provides a simple way to use growthbook features.

=cut

# singletons

class WebService::GrowthBook {
    field $url :param //= 'https://cdn.growthbook.io';
    field $client_key :param;
    field $features :param //= {};
    field $attributes :param :reader :writer //= {};
    field $cache_ttl :param //= 60;
    field $cache //= WebService::GrowthBook::InMemoryFeatureCache->singleton;
    method load_features {
        my $feature_repository = WebService::GrowthBook::FeatureRepository->new(cache => $cache);
        my $loaded_features = $feature_repository->load_features($url, $client_key, $cache_ttl);
        if($loaded_features){
            $self->set_features($loaded_features);
            return 1;
        }
        return undef;
    }
    method set_features($features_set) {
        $features = {};
        for my $feature_id (keys $features_set->%*) {
            my $feature = $features_set->{$feature_id};
            if(blessed($feature) && $feature->isa('WebService::GrowthBook::Feature')){
                $features->{$feature->id} = $feature;
            }
            else {
                $features->{$feature_id} = WebService::GrowthBook::Feature->new(id => $feature_id, default_value => $feature->{defaultValue}, rules => $feature->{rules});
            }
        }
    }
    
    method is_on($feature_name) {
        my $result = $self->eval_feature($feature_name);
        return undef unless defined($result);
        return $result->on;
    }
    
    method is_off($feature_name) {
        my $result = $self->eval_feature($feature_name);
        return undef unless defined($result);
        return $result->off;
    }
    
    # I don't know why it is called stack. In fact it is a hash/dict
    method $eval_feature($feature_name, $stack){
        $log->debug("Evaluating feature $feature_name");
        if(!exists($features->{$feature_name})){
            $log->debugf("No such feature: %s", $feature_name);
            return undef;
        }

        if ($stack->{$feature_name}) {
            $log->warnf("Cyclic prerequisite detected, stack: %s", $stack);
            return undef;
        }
        
        $stack->{$feature_name} = 1;

        my $feature = $features->{$feature_name};
=pod
        for my $rule (@{$feature->rules}){
            if($rule->condition){
                my $condition = $rule->condition;
                my $result = $self->eval_condition($condition, $stack);
                if($result){
                    return WebService::GrowthBook::FeatureResult->new(
                        id => $feature_name,
                        value => $rule->value,
                        on => 1,
                        off => 0);
                }
            }
        }
=cut

        my $default_value = $feature->default_value;
    
        return WebService::GrowthBook::FeatureResult->new(
            id => $feature_name,
            value => $default_value);
    }
     method eval_feature($feature_name){
        return $self->$eval_feature($feature_name, {});
    }
   
    method get_feature_value($feature_name, $fallback = undef){
        my $result = $self->eval_feature($feature_name);
        return $fallback unless defined($result);
        return $result->value;
    }
}

=head1 METHODS

=head2 load_features

load features from growthbook API

    $instance->load_features;

=head2 is_on

check if a feature is on

    $instance->is_on('feature_name');

Please note it will return undef if the feature does not exist.

=head2 is_off

check if a feature is off

    $instance->is_off('feature_name');

Please note it will return undef if the feature does not exist.

=head2 get_feature_value

get the value of a feature

    $instance->get_feature_value('feature_name');

Please note it will return undef if the feature does not exist.

=head2 set_features

set features

    $instance->set_features($features);

=head2 eval_feature

evaluate a feature to get the value

    $instance->eval_feature('feature_name');

=cut

1;


=head1 SEE ALSO

=over 4

=item * L<https://docs.growthbook.io/>

=item * L<PYTHON VERSION|https://github.com/growthbook/growthbook-python>

=back

