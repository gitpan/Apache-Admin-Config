package Apache::Admin::Config;

BEGIN
{
    use 5.005;
    use strict;

    $Apache::Admin::Config::VERSION = '0.06';
    $Apache::Admin::Config::DEBUG   = 0;
}


=pod

=head1 NAME

Apache::Admin::Config - A common module to manipulate Apache configuration files

=head1 SYNOPSIS

    use Apache::Admin::Config;

    my $obj = new Apache::Admin::Config ("/path/to/config_file.conf")
        || die $Apache::Admin::Config::ERROR;

    # getting the full list of directives in current context die if error
    my @directives_list = @{ $obj->directive || die $obj->error };

    # getting the full list of sections in current context or die if error
    my @sections_list = @{ $obj->section || dit $obj->error };


    # getting values' list of directive "Foo"
    my @foo_directive_values = @{ $obj->directive('Foo') };

    # getting values' list of section "Foo"
    my @foo_section_values = @{ $obj->section('Foo') };
    

    # adding directive "Foo" with value "bar" in the current context
    $obj->add_directive(Foo=>'bar');
    # adding directive "Foo" with value "bar" in the section <VirtualHost test.com> 
    # of current context
    $obj->section(VirtualHost=>'test.com')->add_directive(Foo=>'bar');

    # adding section "Foo" with value "bar" in the current context
    $obj->add_section(Foo=>'bar');
    # adding section "Foo" with value "bar" in the section <VirtualHost text.com>
    # of current context (in two steps)
    my $subsection = $obj->section(VirtualHost=>'test.com');
    $subsection->add_section(Foo=>'bar');

    # change directive "Foo" with value "bar" to value "rab"
    $obj->directive(Foo=>'bar')->value('rab');
    # same in sub-section
    $obj->section(VirtualHost=>'test.com')->directive(Foo=>'bar')->value('rab');
    
    # change section "Foo" with value "bar" to value "rab"
    $obj->section(Foo=>'bar')->value('rab');

    # delete directive "Foo bar" (the last one if serveral identicales)
    $obj->directive(Foo=>'bar')->delete;

    # delete section "<Foo bar>...</bar>" (all sections if dispatched several
    # sections with same name/value)
    $obj->section(Foo=>'bar')->delete;
    
    # save changes in the file
    $apache_conf->save;
    # or in another file
    $apache_conf->save('/path/to/another/file.conf');

=head1 DESCRIPTION

This module allows you to edit Apache configuration files without modifying
comments, indentation, or truncated lines. 

=head1 METHODES

=head2 new [/path/to/file]

Create or read, if given in argument, an apache like configuration file.

=cut

sub new 
{
    my $pkg  = shift;
    my $self = bless({}, ref($pkg) || $pkg);
    $self->{htaccess} = $htaccess = shift;

    $self->{level}    = '';
    $self->{master}   = $self;
    $self->{type}     = 'master';

    if(defined $htaccess && -f $htaccess)
    {
        return $self->_set_error('htaccess not readable') unless(-r _);
        $self->_load || return undef;
    }
    else
    {
        $self->_init || return undef;
    }
    
    return($self);
}

=pod

=head2 save [/path/to/file]

Write modifications to the configuration file. If a path to a file is given,
save the modification to this file instead.

=cut

sub save
{
    my $self = shift;
    my $saveas = shift;
    return($self->_set_error('only root object can call save methode')) unless($self->{type} eq 'master');

    my $htaccess = defined $saveas ? $saveas : $self->{htaccess};

    return $self->_set_error("you have to specify a location for writing configuration") unless defined $htaccess;

    open(HTACCESS, ">$htaccess") or return $self->_set_error('can\'t open htaccess file for read');
    foreach(@{$self->{master}->{contents_raw}})
    {
        print HTACCESS "$_\n";
    }
    close(HTACCESS);

    return 1;
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

    $obj->add_section(foo=>'bar')

Add the section named "foo" with value "bar" to the context pointed by $obj.

=cut

sub add_section
{
    section(@_[0..2], 1);
}

=pod

=head2 section [name], [value]

    @sections_list      = @{ $obj->section };
    @section_values     = @{ $obj->section(SectionName) };
    $section_object     = $obj->section(SectionName=>'value');

arguments:

name    : the name of section, it's "File" in section <File "/path/to/file"></File</File>
value   : the value of the section

This method return :

=over 4

=item -

list of sections in current context - as an array reference - if no argument is given.

=item -

list of sections "foo"'s values - as an array reference - if the only argument is "foo"

=item -

an object for the context pointed by the section "foo" with value "bar" if arguments
given was "foo" and "bar".

=back

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

    $obj->add_directive(foo=>'bar');

Add the directive "foo" with value "bar" in the context pointed by $obj.

=cut

sub add_directive
{
    directive(@_[0..2], 1);
}

=pod

=head2 directive

    @directives_list    = @{ $obj->directive };
    @directive_values   = @{ $obj->directive(Foo);
    $directvie_object   = $obj->directive(Foo=>'bar');

Arguments:

name    : the name of directive.
value   : value of the directive.

This method return :

=over 4

=item -

list of directives in context pointed by $obj - as an array reference - if no argument is given.

=item -

list of "foo" directive's values - as an array reference - if the only argument is "foo".

=item -

an object for manipulating directive called "foo" with value "bar" if arguments
given was "foo" and "bar". Warning, if several directive have the same name and
value, the last one is taken, may change in future versions.

=back

=cut

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
                    if($root->{$directive}->[$i]->[0] eq $value)
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
            return [$root->{$directive} ? map($_->[0], @{$root->{$directive}}) : ()];
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

=head2 delete

    $htconf->directive('AddType'=>'.pl')->delete;
    $htconf->section('File'=>'/path/to/file')->delete;

Delete the current context pointed by object. Can be directive or section.

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

=head2 value [newvalue]

    $htconf->directive('File'=>'/path/to/foo')->value('/path/to/bar');

Change the value of a directive or section. If no argument given, return
the value of object $htconf.

=cut

sub value
{
    my $self     = shift;
    my $newvalue = shift || return $self->{value};
    my $master   = $self->{master};
    my $root     = $self->_root or return undef;
    
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
            splice(@{$master->{contents_raw}}, $offset, $length, $self->write_section($self->{name}, $newvalue));
            $trunc += $lenfth - 1; # if line taken more than one line, keep trace of remainder
        }
    }
    elsif($self->{type} eq 'directive')
    {
        my $offset = $root->[1]->[0];
        my $length = $root->[1]->[-1] - $offset + 1;
        splice(@{$master->{contents_raw}}, $offset, $length, $self->write_directive($self->{name}, $newvalue));
    }
    else
    {
        return($self->_set_error('methode not allowed'));
    }

    $self->_parse;
}

=pod

=head2 error

Return the last append error.

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
        if($line =~ /^(\w+)\s*(.*)$/)
        {
            my $directive = lc($1);
            my $value = defined $2 ? $2 : '';
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

sub _init
{
    my $self = shift;
    $self->{master}->{contents_raw} = [];
    return $self->_parse;
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
Revision 1.17  2001/09/17 23:44:06  rs
minor bugfix

Revision 1.16  2001/09/17 23:12:53  rs
Make a real quick and dirty documentation
value() now return the context value if called without arguments
new() can now be called without arguments, save() need one in this case

Revision 1.15  2001/08/23 01:05:35  rs
update of documentation's DESCRIPTION section

Revision 1.14  2001/08/18 13:38:25  rs
fix major bug, if config file wasn't exist, module won't work

Revision 1.13  2001/08/18 12:50:14  rs
value method wasn't take the appropriate value for change it

Revision 1.12  2001/08/18 12:46:15  rs
$root value was not defined !

Revision 1.11  2001/08/18 12:39:35  rs
migrate to 0.05

Revision 1.10  2001/08/18 12:39:15  rs
bug fix in value method, $master wasn't defined, cause method to not work
at all

Revision 1.9  2001/08/16 23:41:59  rs
fix bug in directive method :
directive foo doesn't exists
@{$conf->directive("foo")};
$conf->add_directive(foo=>'bar');
Modification of non-creatable array value attempted, subscript -1 at ... line 358.

Revision 1.8  2001/08/16 23:07:04  rs
fix a bug in directive methode.

Revision 1.7  2001/08/15 23:48:33  rs
Fix a major bug that cause "syntaxe error" on directives that haven't values
like "clearmodulelist"

Revision 1.6  2001/08/14 09:49:07  rs
adding some pod sections

