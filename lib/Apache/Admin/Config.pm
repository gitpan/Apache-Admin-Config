package Apache::Admin::Config;

BEGIN
{
    use 5.005;
    use strict;

    $Apache::Admin::Config::VERSION = '0.01';
    $Apache::Admin::Config::DEBUG   = 0;
}


=pod

=head1 NAME

Apache::Admin::Config - A common module for manipulate Apache configurations files

=head1 SYNOPSIS

    use Apache::Admin::Config;

    my $apache_conf = new Apache::Admin::Config ("/path/to/config_file.conf");

    # parsing contents
    my @directives      = @{ $apache_conf->directive() || die $apache_conf->error };
    my @sections        = @{ $apache_conf->section() || die $apache_conf->error };
    my @file_sections   = @{ $apache_conf->section('file') || die $apache_conf->error };

    # parsing file section contents
    my @file_directives = @{ $apache_conf->section(file=>$file_sections[0])->directive };
    my @file_sections   = @{ $apache_conf->section(file=>$file_sections[0])->section };

    # adding directive/section
    $apache_conf->add_directive(Options=>'+Indexes');
    $apache_conf->section(File=>'/some/file')->add_directive(Allow=>'from all');

    $apache_conf->add_section(File=>'/some/file');
    $apache_conf->section(VirtualHost=>'some.host')->add_section(File=>'/some/file');

    # change directive value
    $apache_conf->directive(Options=>'+Indexes')->value('+Indexes -FollowSymlinks');
    $apache_conf->section(File=>'/some/file')->directive(Allow=>'from all')->value('from 127.0.0.1');
    
    $apache_conf->section(File=>'/some/file')->value('/some/other/file');
    $apache_conf->section(VirtualHost=>'some.host')->section(File=>'/some/file')->value('/some/other/file');

    # delete directive (the last one if more than one identicales)
    $apache_conf->directive(Options=>'+Indexes')->delete;
    $apache_conf->section(File=>'/some/file')->directive(Allow=>'from all')->delete;

    $apache_conf->section(File=>'/some/file')->delete;
    $apache_conf->section(VirtualHost=>'some.host')->section(File=>'/some/file')->delete;

=head1 DESCRIPTION

under construction

=head1 METHODES

=head2 new

under construction

=cut

sub new 
{
    my $pkg  = shift;
    my $self = bless({}, ref($pkg) || $pkg);
    $self->{htaccess} = $htaccess = shift || return $self->_set_error('too few arguments');

    $self->{level}    = '';
    $self->{master}   = $self;
    $self->{type}     = 'master';

    if(-f $htaccess)
    {
        return $self->_set_error('htaccess not readable') unless(-r _);
        $self->_load || return undef;
    }
    
    return($self);
}

=pod

=head2 save

under construction

=cut

sub save
{
    my $self = shift;
    my $saveas = shift;
    return($self->_set_error('only root object can call save methode')) unless($self->{type} eq 'master');

    my $htaccess = defined $saveas ? $saveas : $self->{htaccess};

    open(HTACCESS, ">$htaccess") or return $self->_set_error('can\'t open htaccess file for read');
    foreach(@{$self->{master}->{contents_raw}})
    {
        print HTACCESS "$_\n";
    }
    close(HTACCESS);

    return 1;
}

=pod

=head2 delete

under construction

=cut

sub delete
{
    my $self   = shift;
    my $root   = $self->_root || return undef;
    my $master = $self->{master};
    my $deleted= 0;

    if($self->{type} eq 'section')
    {
        my $lines   = $root->{_pos};
        for(my $i = 0; $i < @$lines; $i++)
        {
            my $offset = $lines->[$i]->[0]; # first section opener tag's line (for trucated line) 
            my $length = $lines->[++$i]->[-1] - $offset + 1; # last section closer tag's line (for trucated line)
            $offset -= $deleted;
            splice(@{$master->{contents_raw}}, $offset, $length);
            $deleted += $length;
        }
    }
    elsif($self->{type} eq 'directive')
    {
        my $offset = $root->[1]->[0];
        my $length = $root->[1]->[-1] - $offset + 1;
        splice(@{$master->{contents_raw}}, $offset, $length);
        $deleted = $length;
    }
    else
    {
        return($self->_set_error('methode not allowed'));
    }

    $self->_parse;
    undef($_[0]);
    return($deleted);
}

=pod

=head2 value

under construction

=cut

sub value
{
    my $self     = shift;
    my $newvalue = shift;
    
    if($self->{type} eq 'section')
    {
        my $lines   = $root->{_pos};
        my $trunc   = 0;
        for(my $i = 0; $i < @$lines; $i++)
        {
            my $offset = $lines->[$i]->[0]; # first section opener tag's line 
            my $length = $lines->[$i++]->[-1] - $offset + 1; # last section section opener tag's line (often the same as first)
            # if the line was truncated, we replace it by a single line
            $offset -= $trunc;
            splice(@{$master->{contents_raw}}, $offset, $length, $self->write_section($self->{name}, $self->{value}));
            $trunc += $lenfth - 1; # if line taken more than one line, keep trace of remainder
        }
    }
    elsif($self->{type} eq 'directive')
    {
        my $offset = $root->[1]->[0];
        my $length = $root->[1]->[-1] - $offset + 1;
        splice(@{$master->{contents_raw}}, $offset, $length, $self->write_directive($self->{name}, $self->{value}));
    }
    else
    {
        return($self->_set_error('methode not allowed'));
    }

    $self->_parse;
}

sub write_section
{
    # this methode is made for easy sections writing's overload
    # must take 2 arguments (directive name, directive value)
    # and return a string
    my $self  = shift;
    my $name  = shift;
    my $value = shift;
    return("<$name $value>");
}

sub write_section_closer
{
    # this methode is made for easy sections closer writing's overload
    # take 1 argument (directive name) and return string
    my $self = shift;
    my $name = shift;
    return("</$name>");
}

=pod

=head2 add_section

under construction

=cut

sub add_section
{
    section(@_[0..2], 1);
}

=pod

=head2 section

    @sections_name      = $obj->section;
    @sections_entrys    = $obj->section(SectionName);
    $section_object     = $obj->section(SectionName=>'value');

arguments:

name    : the name of section, it's "File" in section <File "/path/to/file"></File</File>
value   : the value of the section

=cut

sub section
{
    my($self, $section, $entry, $add) = @_;
    return($self->_set_error('methode not allowed')) if($self->{type} eq 'directive');
    $section = lc $section if(defined $section);
    my $master  = $self->{master};
    my $root    = $self->_root || return undef;

    if(defined $section && defined $entry)
    {
        if(defined($add) && $add)
        {
            # add
            return($self->_set_error('can\'t add section, it already exists'))
              if(defined $root->{$section} && defined $root->{$section}->{$entry});
            
            my $n = $root->{$section} ? $root->{$section}->{$entry}->{_pos}->[-1]->[-1] :
            $root->{_pos} ? $root->{_pos}->[-1]->[-1] : @{$master->{contents_raw}};
            
            splice(@{$master->{contents_raw}}, $n, 0, $self->write_section($section, $entry), $self->write_section_closer($section));
            $self->_parse;
            $root = $self->_root;
        }
        
        if(defined $root->{$section} && defined $root->{$section}->{$entry})
        {
            # get subsection object
            my $sub = bless({});
            $sub->{level}  .= $self->{level} . "->{'$section'}->{'$entry'}";
            $sub->{master}  = $master;
            $sub->{type}    = 'section';
            $sub->{name}    = $section;
            $sub->{value}   = $entry;
            return($sub);
        }
        else
        {
            return($self->_set_error('section or entry doesn\'t exists'));
        }
    }
    elsif(defined $section)
    {
        return($self->_set_error('section doesn\'t exists')) unless($root->{$section});
        return([keys %{$root->{$section}}]);
    }
    else
    {
        my @section;
        foreach my $k (keys %$root)
        {
            next if($k eq '_pos');
            push(@section, $k) if(ref($root->{$k}) eq 'HASH');
        }
        return(\@section);
    }
}

sub write_directive
{
    # this methode is made for easy directive writing's overload
    my $self  = shift;
    my $name  = shift;
    my $value = shift;
    return("$name $value");
}

=pod

=head2 add_directive

under construction

=cut

sub add_directive
{
    directive(@_[0..2], 1);
}

=pod

=head2 directive

under construction

=cut

# directive(directive=>value, 'add', -section=>'directory.file')
sub directive
{
    my($self, $directive, $value, $add) = @_;
    return($self->_set_error('methode not allowed')) if($self->{type} eq 'directive');
    $directive = lc $directive if(defined $directive);
    my $master = $self->{master};
    my $root = $self->_root || return undef;

    if(defined $directive)
    {
        if(defined $value)
        {
            if(defined $add && $add)
            {
                # if another same directive exists, we want position this one
                # near the last one.
                # else we position this directive on the last line of section, or
                # file.
                my $n = $root->{$directive} 
                  ? $root->{$directive}->[-1]->[1]->[-1]+1 : $root->{_pos} 
                    ? $root->{_pos}->[-1]->[-1] : @{$master->{contents_raw}};
                splice(@{$master->{contents_raw}}, $n, 0, $self->write_directive($directive, $value));
                $self->_parse;
                return 1;
            }
            else
            {
                my @directives  = $self->directive($directive);
                return($self->_set_error('directive doesn\'t exists'))
                  unless(@directives);

                # we search the last directive with this value
                my $index;
                for(my $i = @directives - 1; $i >= 0; $i--)
                {
                    if($root->[$i]->[0] eq $self->{value})
                    {
                        $index = $i;
                        last;
                    }
                }

                return($self->_set_error('directive entry doesn\'t exists'))
                  unless(defined $index);

                my $sub = bless({});
                $sub->{level}   = $self->{level} . "->{'$directive'}->[$index]";
                $sub->{master}  = $self->{master};
                $sub->{type}    = 'directive';
                $sub->{name}    = $directive;
                $sub->{value}   = $value;
                return $sub;
            }
        }
        else
        {
            return [map($_->[0], @{$root->{$directive}})];
        }
    }
    else
    {
        my @directives;
        foreach my $k (keys %$root)
        {
            next if($k eq '_pos');
            push(@directives, $k) if(ref($root->{$k}) eq 'ARRAY');
        }
        return(\@directives);
    }
}

=pod

=head2 error

under construction

=cut

sub error
{
    return $_[0]->{master}->{__last_error__};
}

sub _root
{
    my $self = shift;
    
    my $root;
    eval('$root=$self->{master}->{contents_parsed}'.$self->{level});
    return($self->_set_error('can\'t get root')) unless(defined $root && ref $root);
    return($root);
}

sub _parse
{
    my $self = shift;
    my @htaccess = @{$self->{master}->{contents_raw}};

    my %contents_parsed;
    # level is used to stock reference to the curent level, level[0] is the root level
    my @level = (\%contents_parsed);
    # last_section is used to ensure that sections open/close are in correct order
    my @last_section;
    for(my $n = 0; $n < @htaccess; $n++)
    {
        my $line = $htaccess[$n];
        next if($line =~ m/^\s*#/); # ignore comments
        my @_pos = ($n); # initialise position indicator
        while($line =~ s/\\$//)
        {
            # line is truncated, we want the entire line
            $line .= $htaccess[++$n];
            push(@_pos, $n); # line positionned on multiple lines
        }
        $line =~ s/^\s*|\s*$//g;
        next if($line eq '');
        if($line =~ /^(\w+)\s+(.*)$/)
        {
            my $directive = lc($1);
            my $value = $2;
            $value =~ s/^\s*|\s*$//g;
            # directive exists but is not a directive !
            return $self->_set_error(sprintf('syntaxe error at line %d', $n+1))
              if(defined $level[-1]->{$directive} && ref($level[-1]->{$directive}) ne 'ARRAY');
            push(@{$level[-1]->{$directive}}, [$value, \@_pos]); #[value, line position]
        }
        elsif($line =~ /^<\s*(\w+)\s+([^>]+)>$/)
        {
            my $section = lc($1);
            my $value = $2;
            $value =~ s/^\s*|\s*$//g;
            # section exists, but is not a section !
            return $self->_set_error(sprintf('syntaxe error at line %d', $n+1))
                if(defined $level[-1]->{$section} && ref($level[-1]->{$section}) ne 'HASH');
            push(@level, $level[-1]->{$section}->{$value} ||= {});
            push(@{$level[-1]->{_pos}}, \@_pos); # save the line number of this section
            push(@last_section, $section);
        }
        elsif($line =~ /^<\/\s*(\w+)\s*>$/)
        {
            my $section = lc($1);
            return $self->_set_error(sprintf('syntaxe error at line %d', $n+1)) 
              if(!@last_section || $section ne $last_section[-1]);
            push(@{$level[-1]->{_pos}}, \@_pos); # save last line of section
            pop(@last_section);
            pop(@level);
        }
        else
        {
            return $self->_set_error(sprintf('syntaxe error at line %d', $n+1));
        }
    }

    eval('use Data::Dumper; print Data::Dumper::Dumper(\%contents_parsed), "\n";') if($Apache::Admin::Config::DEBUG);

    $self->{master}->{contents_parsed} = \%contents_parsed;

    return 1;
}

sub _load
{
    my $self = shift;
    my $htaccess = $self->{htaccess};
    my @htaccess;

    open(HTACCESS, $htaccess) or return $self->_set_error('can\'t open htaccess file for read');
    while(<HTACCESS>)
    {
        chomp;
        push(@htaccess, $_);
    }
    close(HTACCESS);
    $self->{master}->{contents_raw} = \@htaccess;
    return $self->_parse;
}

sub _set_error
{
    my $self = shift;
    $Apache::Admin::Config::ERROR = $self->{master}->{__last_error__} = join('', (caller())[0].': ', @_);
    return(undef);
}

DESTROY
{
    undef($_[0]->{master});
}

1;

=pod

=head1 AUTHOR

Olivier Poitrey E<lt>rs@rhapsodyk.netE<gt>

=head1 LICENCE

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with the program; if not, write to the Free Software
Foundation, Inc. :

59 Temple Place, Suite 330, Boston, MA 02111-1307

=head1 COPYRIGHT

Copyright (C) 2001 - Olivier Poitrey

=head1 HISTORY

$Log: Config.pm,v $
Revision 1.6  2001/08/14 09:49:07  rs
adding some pod sections

