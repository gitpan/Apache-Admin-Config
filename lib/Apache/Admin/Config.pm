package Apache::Admin::Config;

BEGIN
{
    use 5.005;
    use strict;
    use FileHandle;
    use overload nomethod => \&to_string;

    $Apache::Admin::Config::VERSION = '0.20';
    $Apache::Admin::Config::DEBUG   = 0;
}


=pod

=head1 NAME

Apache::Admin::Config - A common module to manipulate Apache configuration files

=head1 SYNOPSIS

    use Apache::Admin::Config;

    # Parse an apache configuration file
    my $obj = new Apache::Admin::Config ("/path/to/config_file.conf")
        or die $Apache::Admin::Config::ERROR;

    # or parse a filehandle
    open(ANHANDLE, "/path/to/a/file")...
    ...
    my $obj = new Apache::Admin::Config (\*ANHANDLE)
        or die $Apache::Admin::Config::ERROR;


    #
    # working with directives
    #


    # Getting the full list of directives in current context. 

    # Directive method called without any argument, return a list
    # of all directive located in the current context. The actual
    # context is called "top", because it haven't any parent.
    my @directives_list = $obj->directive;

    # The resulting array, is sorted by order of apparence in the
    # file. So you can easly figure directive's precedence.

    # Each item of @directives_list array is a "magic" string. If
    # you print one, it return the name of pointed directive.
    my $directive = $directives_list[3];
    print $directive; # return "DocumentRoot" for example

    # But this "magic" string is also an object, that have many
    # methods for manage this directive.
    print $directive->value;  # "/my/document/root"
    print $directive->type;   # "directive"
    $directive->isin($obj);   # true
    $directive->delete;
    ...
    
    # this print all current context's directives and it's associated
    # value :
    foreach my $directive ($obj->directive)
    {
        printf qq(%s: '%s' has value: '%s' at line %d\n), 
            $directive->type, $directive->name, $directive->value, $directive->first_line;
    }
    
    # possible output:
    directive: servertype has value: standalone at line 48
    directive: serverroot has value: "@@ServerRoot@@" at line 61
    directive: pidfile has value: logs/httpd.pid at line 78
    directive: scoreboardfile has value: logs/apache_runtime_status at line 86
    ...
    
    # you can select which directive you want
    my $directive = $obj->directive(-which=>8); # you'll get the 8th directive of
                                                # the current context
    

    # getting the full list of directive who's name is "Foo" in the current context
    my @foo_directives = $obj->directive('Foo');
    # or just the 4th
    my $4th_foo_directive = $obj->directive('Foo', -which=>4);


    # you may want just directives named "Foo" with value "Bar", it return
    # a list of all directives with these name/value in list context
    my @foo_bar_directives = $obj->directive(Foo=>'Bar');
    # or just the last one in scalar context
    my $foo_bar_directive = $obj->directive(Foo=>'Bar');
    # or the second one if "-which" option is given.
    my $foo_bar_directive = $obj->directive(Foo=>'Bar', -which=>2);

    # working on directive "PidFile"
    my $pidfile = $obj->directive(PidFile=>'logs/httpd.pid');

    # changing value of directive "PidFile logs/httpd.pid" to "PidFile logs/apache.pid"
    $pidfile->set_value('logs/apache.pid');


    # deleting directive "PidFile logs/apache.pid"
    $pidfile->delete;

    # or deleting all directives "AddType"
    map($_->delete, $obj->directive(AddType)); # dangerous


    # adding directive "AddType text/html .shtml" just after the last AddType directive if any
    # or at the end of file (or section)
    $obj->add_directive(AddType=>'text/html .shtml', -after=>$obj->directive('AddType', -which=>-1))
    # only if "AddType text/html .shtml" doesn't exist
    unless($obj->directive(AddType=>'text/html .shtml'));

    #
    # working with sections
    #

    # you can get object to another context like this
    my $section_directive_foo = $obj->section(Foo=>'Bar');
    my @directives_list = $section_directive_foo->directive;

    # accessing the section "<file some_file>" in the section "<directory /some/dir>" 
    # of section "<virtualhost example.com>"
    my $subsubsubsection = $obj->section(virtualhost=>"example.com")->section(directory=>"/some/dir")->section(file=>"some_file")

    #
    # reordering lines
    # 

    # moving all directives "LoadModule" before directives "AddModule" in the current context
    my $first_addmodule = $obj->directive(AddModule, -which=>0):
    foreach my $loadmodule ($obj->directive('LoadModule'))
    {
        $loadmodule->move(-before=>$first_addmodule);
          if($loadmodule->line > $first_addmodule->line);
    }
    
    #
    # save
    #

    # save change in place
    $obj->save;
    # or in another file (sound like "save as...")
    $obj->save("/path/to/another/file");
    # or in an already openned file
    $obj->save(\*FILE_HANDLE);

=head1 DESCRIPTION

C<Apache::Admin::Config> provides an object interface to handling Apache like
configuration files without modifying comments, identation, or truncated lines.

=head1 METHODES

=head2 new ([I</path/to/file>|I<handle>], B<-oldapi>=>I<0|1>)

Create or read, if given in argument, an apache like configuration file.

Arguments:

=over 4

=item I<C</path/to/file>>

Path to the configuration file to parse. If none given, create a new one.

= item I<C<handle>>

Instead of specify a path to a file, you can give a reference to an handle that
point to an already openned file. You can do this like this :

    my $conf = new Apache::Admin::Config (\*MYHANDLE);

=item I<B<-oldapi>>=E<gt>I<0/1>

If true, keep the old api backward compatibility. Read UPGRADE-0.10 for more details.
Default is false.

=back

=cut

sub new 
{
    my $pkg  = shift;
    my $self = bless({}, ref($pkg) || $pkg);

    $self->{oldapi} = _get_arg(\@_, '-oldapi');
    
    $self->{htaccess} = $htaccess = shift;

    $self->{level} = '';
    $self->{top}   = $self;
    $self->{type}  = 'top';

    if(defined $htaccess && (ref $htaccess eq 'GLOB' || -f $htaccess)) # trying to handle GLOBs
    {
        $self->_load || return undef;
    }
    else # if htaccess doesn't exists, init new one
    {
        $self->_init || return undef;
    }
    
    return($self);
}

=pod

=head2 save ([I</path/to/file>|I<HANDLE>])

Write modifications to the configuration file. If a path to a file is given,
save the modification to this file instead. You also can give a reference to
a filehandle like this :

    $conf->save(\*MYHANDLE) or die($conf->error);

=cut

sub save
{
    my $self = shift;
    my $saveas = shift;
    return($self->_set_error('only root object can call save method')) unless($self->{type} eq 'top');

    my $htaccess = defined $saveas ? $saveas : $self->{htaccess};

    return $self->_set_error("you have to specify a location for writing configuration") unless defined $htaccess;

    my $fh;

    if(ref $htaccess eq 'GLOB')
    {
        $fh = $htaccess;
    }
    else
    {
        $fh = new FileHandle(">$htaccess") or return $self->_set_error("can't open `$htaccess' file for read");
    }

    print $fh $self->dump_raw;

    return 1;
}

=pod

=head2 dump_raw

Return the configuration file as same as it will be if it saved in a file with the
B<save()> method.

=cut

sub dump_raw
{
    my($self) = @_;
    return($self->_set_error('only root object can call dump_raw method')) unless($self->{type} eq 'top');

    return(join('', map("$_\n", @{$self->{top}->{contents_raw}})));
}

sub dump_struct
{
    my($self) = @_;
    eval('use Data::Dumper; Data::Dumper::Dumper($self->{top}->{contents_parsed}), "\n";');
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

sub write_section_closing
{
    # this methode is made for easy sections closer writing's overload
    # take 1 argument (directive name) and return string
    my $self = shift;
    my $name = shift;
    return("</$name>");
}

=pod

=head2 add_section (I<name>=>I<'value'>, [B<-before>=>I<target> | B<-after>=>I<target> | B<-ontop> | B<-onbottom>])

    $obj->add_section(foo=>'bar', -after=>$obj->directive('oof', -which=>-1));

Add the directive I<foo> with value I<bar> in the context pointed by B<$obj>.

Aguments:

=over 4

=item B<C<name>>

Section's name to add.

=item B<C<value>>

Value associated with this section's name

=item B<C<-before>>=E<gt>I<target>

insert section one line before I<target> if is in same context;

=item B<C<-after>>=E<gt>I<target>

insert section one line after I<target> if is in same context;

=item B<C<-ontop>>

insert section on the fist line of current context;

=item B<C<-onbottom>>

insert section on the last line of current context;

=back

Return the added section

=cut

sub add_section
{
    my $self = shift;

    my($target, $type) = _get_arg(\@_, '-before|-after|-ontop!|-onbottom!');

    # _get_arg return undef on error or empty string on not founded rule
    return($self->_set_error('malformed arguments')) if(not defined $target);

    return($self->_set_error('too many arguments')) if(@_ > 2);
    my($section_name, $entry) = @_;

    return($self->_set_error('method not allowed')) if($self->{type} eq 'directive');
    return($self->_set_error('too few arguments')) unless defined $section_name;
    $section_name = lc $section_name;
    #my $typed_section = _type($section, 'section');

    #return($self->_set_error('can\'t add section, it already exists'))
    #  if(defined $root->{$typed_section} && defined $root->{$typed_section}->{$entry});

    my $insert_line;
    $type = defined $type ? $type : '-onbottom'; # default behavior
    if(($type eq '-before' || $type eq '-after')
        && defined $target && ref $target && $target->isa(Apache::Admin::Config)
        && $target->isin($self))
    {
        $insert_line = $type eq '-before' ? $target->first_line : $target->last_line + 1;
    }
    else
    {
        $insert_line = $type eq '-ontop' || $type eq '-after' ? $self->first_line : 
            # in sections, last line return the closer, and we want live one line before it
            ($self->type eq 'top' ? $self->last_line + 1 : $self->last_line + 0);
    }
    
    my $which = $self->_get_section_before_line($section_name, $insert_line);
    
    $self->_insert_line
    (
        $insert_line, 
        $self->write_section($section_name, $entry),
        $self->write_section_closing($section_name)
    );

    my $index = $insert_line == 0 ? $insert_line : $insert_line-1;
    my $new_section_hashref = _insert_section($self->_root, $section_name, $entry, [$index]);
    _insert_section_closer($new_section_hashref, [$index+1]);

    return($self->section($section_name, $entry, ($which ? ('-which',$which) : ())));
}

sub _get_section_before_line
{
    my($self, $section_name, $line) = @_;
    my $root = $self->_root;

    my $n = 0;
    foreach (_get_sections($root))
    {
        my($sec_tag, $sec_pos) = @$_[0,2];
        my $sec_name = _untype($sec_tag, 'section');
        next unless $sec_name eq $section_name;
        $n++;
        my $secline = $sec_pos->[-1]->[-1]+1;
        return $n-1 if($secline > $line)
    }

    return $n;
}

=pod

=head2 section ([[I<name>], I<value>], [B<-which>=>I<number>])

    @sections_list      = $obj->section;
    @section_values     = $obj->section(SectionName);
    $section_object     = $obj->section(SectionName=>'value');

arguments:

=over 4

=item - B<C<name>>

the name of section, it's B<File> in section E<lt>File "I</path/to/file>"E<gt>

=item - B<C<value>>

the value of the section

=back

This method return :

=over 4

=item -

list of sections in current context if no argument is given.

=item -

list of sections I<foo>'s values if the only argument is I<foo>.

return a list in list context and a reference to an array in scalar context.

=item -

an object for the context pointed by the section I<foo> with value I<bar> if arguments
given was I<foo> and I<bar>.

=back

=cut

sub section
{
    my $self  = shift;

    my $which = _get_arg(\@_, '-which');

    # _get_arg return undef on error or empty string on not founded rule
    return($self->_set_error('malformed arguments')) if(not defined $which); 
    # $which isn't an integer
    return($self->_set_error('wrong type for "which" argument')) if($which =~ /[^\d\-]/);
    
    return($self->_set_error('too many arguments')) if(@_ > 2);
    my($section_name, $entry) = @_;
    
    return($self->_set_error('method not allowed')) if($self->{type} eq 'directive');
    $section_name = lc $section_name if defined $section_name;
    #$section = _type(lc($section), 'section') if(defined $section);
    my $top  = $self->{top};
    my $root = $self->_root || return undef;

    if(defined $section_name)
    {
        if(defined $entry)
        {
            return($self->_set_error("section `$section_name' doesn't exists"))
                unless exists $root->{_sections_counter}->{$section_name};

            my @sections = $self->section($section_name);
            my $section;
            if(@sections)
            {
                if(length $which)
                {
                    my $n = 1;
                    foreach $section (@sections)
                    {
                        next unless $section->value eq $entry;
                        return $section if $n++ == $which;
                    }
                }
                else
                {
                    foreach $section (reverse @sections)
                    {
                        return $section if $section->value eq $entry;
                    }
                }
            }
            return $self->_set_error
            (
                "section entry `<$section_name $entry>' doesn\'t exists".
                (length $which ? " at `$which' position" : '')
            );
        }
        else
        {
            return($self->_set_error("section `$section_name' doesn\'t exists"))
                unless($root->{_sections_counter}->{$section_name});

            my @section_values;
            my $n = 0;
            foreach(_get_sections($root))
            {
                my($sec_tag, $sec_val) = @$_;
                my $sec_name = _untype($sec_tag, 'section');
                next unless($sec_name eq $section_name);

                if(length $which)
                {
                    next unless $n++ == $which;
                }

                my $sub = bless({});
                $sub->{level}     = sprintf(q(%s->{'%s'}), $self->{level}, $sec_tag);
                $sub->{top}       = $top;
                $sub->{parent}    = $self;
                $sub->{type}      = 'section';
                $sub->{name}      = $sec_tag;
                $sub->{value}     = $sec_val;
                $sub->{to_string} = $sub->{value};

                $which eq '' ? push(@section_values, $sub) : return $sub;
            }
            
            return(wantarray ? @section_values : ($self->{oldapi} ? \@section_values : @section_values));
        }
    }
    else
    {
        if(not length $which)
        {
            my @sections;
            foreach(_get_sections($root))
            {
                my($sec_tag, $sec_val) = @$_;
                my $sec_name = _untype($sec_tag, 'section');
                my $sub = bless({});
                $sub->{level}     = sprintf(q(%s->{'%s'}), $self->{level}, $sec_tag);
                $sub->{top}       = $top;
                $sub->{parent}    = $self;
                $sub->{type}      = 'section';
                $sub->{name}      = $sec_tag;
                $sub->{value}     = $sec_val;
                $sub->{to_string} = $sec_name;

                # with new api, we have to return the last element in scalar context like normal
                # list in scalar context. So we don't bless all unwanted objects instances.
                return $sub if(!$self->{oldapi} && !wantarray);

                push(@sections, $sub);
            }
            
            return(wantarray ? @sections : ($self->{oldapi} ? \@sections : @sections));
        }
        else
        {
            my @sections = _get_sections($root);
            if(defined $sections[$which])
            {
                my($sec_tag, $sec_val) = $sections[$which];
                my $sec_name = _untype($sec_tag, 'section');
                my $sub = bless({});
                $sub->{level}     = sprintf(q(%s->{'%s'}), $self->{level}, $sec_tag);
                $sub->{top}       = $top;
                $sub->{parent}    = $self;
                $sub->{type}      = 'section';
                $sub->{name}      = $sec_tag;
                $sub->{value}     = $sec_val;
                $sub->{to_string} = $sec_name;
                return $sub;
            }
            else
            {
                return $self->_set_error("section doesn\'t exists at index `$which'");
            }
        }
    }
}

sub write_directive
{
    # this methode is made for easy directive writing's overload
    my($self, $name, $value) = @_;
    return undef unless defined $name;
    $value = defined $value ? $value : '';
    return("$name $value");
}

=pod

=head2 add_directive (I<name>=>I<'value'>, [B<-before>=>I<target> | B<-after>=>I<target> | B<-ontop> | B<-onbottom>])

    $obj->add_directive(foo=>'bar', -after=>$obj->directive('oof', -which=>-1));

Add the directive I<foo> with value I<bar> in the context pointed by B<$obj>.

Aguments:

=over 4

=item B<C<name>>

Directive's name to add.

=item B<C<value>>

Value associated with this directive's name

=item B<C<-before>>=E<gt>I<target>

insert directive one line before I<target> if is in same context;

=item B<C<-after>>=E<gt>I<target>

insert directive one line after I<target> if is in same context;

=item B<C<-ontop>>

insert directive on the fist line of current context;

=item B<C<-onbottom>>

insert directive on the last line of current context;

=back

Return the added directive.

=cut

sub add_directive
{
    my $self = shift;
    
    my($target, $type) = _get_arg(\@_, '-before|-after|-ontop!|-onbottom!');

    # _get_arg return undef on error or empty string on not founded rule
    return($self->_set_error('malformed arguments')) if(not defined $target);

    return($self->_set_error('to many arguments')) if(@_ > 2);
    my($directive, $value) = @_;
    
    return($self->_set_error('methode not allowed')) if($self->{type} eq 'directive');
    $directive = lc $directive if(defined $directive);
    return($self->_set_error('to few arguments')) unless defined $directive;
    
    my $insert_line;
    $type = defined $type ? $type : '-onbottom'; # default behavior
    if(($type eq '-before' || $type eq '-after') 
        && defined $target && ref $target && $target->isa(Apache::Admin::Config)
        && $target->isin($self))
    {
        $insert_line = $type eq '-before' ? $target->first_line : $target->last_line + 1;
    }
    else
    {
        $insert_line = $type eq '-ontop' || $type eq '-after' ? $self->first_line : $self->last_line + 1;
    }

    $self->_insert_line($insert_line, $self->write_directive($directive, $value));
    _insert_directive($self->_root, $directive, $value, [$insert_line == 0 ? $insert_line : $insert_line-1]);

    return($self->directive($directive, $value));
}


=pod

=head2 directive ([[I<name>], I<value>], [B<-which>=>I<number>])

    @directives_list    = $obj->directive;
    @directive_values   = $obj->directive(Foo);
    $directvie_object   = $obj->directive(Foo=>'bar');

Arguments:

=over 4

=item B<C<name>>

the name of directive.

=item B<C<value>>

value of the directive.

=back

This method return :

=over 4

=item -

list of directives in context pointed by B<$obj> if no argument is given.

return a list in list context and a reference to an array in scalar context.

=item -

list of I<foo> directive's values if the only argument is I<foo>.

return a list in list context and a reference to an array in scalar context.

=item -

an object for handling directive called I<foo> with value I<bar> if arguments
given was I<foo> and I<bar>. Warning, if several directive have the same name and
value, the last one is taken, may change in future versions.

=back

=cut

sub directive
{
    my $self    = shift;
    
    my $which   = _get_arg(\@_, '-which');

    # _get_arg return undef on error or empty string on not founded rule
    return($self->_set_error('malformed arguments')) if(not defined $which); 
    # $which isn't an integer
    return($self->_set_error('wrong type for "which" argument')) if($which =~ /[^\d\-]/);
    
    return($self->_set_error('too many arguments')) if(@_ > 2);
    my($directive, $value) = @_;
    
    return($self->_set_error('method not allowed')) if($self->{type} eq 'directive');
    $directive = _type(lc($directive), 'directive') if(defined $directive);
    my $top  = $self->{top};
    my $root = $self->_root || return undef;

    if(defined $directive)
    {
        if(defined $value)
        {
            # called like this: $obj->directive(Foo, Bar [, -which=>n])
            my @directives  = $self->directive(_untype($directive, 'directive'));
            return($self->_set_error('directive doesn\'t exists'))
              unless(@directives);

            # get a list of all values $value of directive $directive
            my @values_index;
            for(my $i = 0; $i < @directives; $i++)
            {
                push(@values_index, $i) if($root->{$directive}->[$i]->[0] eq $value);
            }

            # if -which not specified, return the last value
            my $index = $which eq '' ? $values_index[-1] : $values_index[$which];

            return($self->_set_error('directive entry doesn\'t exists'))
              unless(defined $index);

            my $sub = bless({});
            $sub->{level}     = sprintf(q(%s->{'%s'}->[%d]), $self->{level}, $directive, $index);
            $sub->{top}       = $self->{top};
            $sub->{parent}    = $self;
            $sub->{type}      = 'directive';
            $sub->{name}      = $directive;
            $sub->{value}     = $value;
            $sub->{to_string} = $sub->{value};
            return $sub;
        }
        else
        {
            return($self->_set_error('directive doesn\'t exists')) unless exists $root->{$directive};
            if($which eq '')
            {
                # called like this: $obj->directive(Foo)
                my @directive_values;

                for(my $n = $#{$root->{$directive}}; $n >= 0; $n--)
                {
                    next if($genone && $n != $dircnt-1); # don't bless all objects if user
                                                         # want only the last one (new API)
                    my $sub = bless({});
                    $sub->{level}     = sprintf(q(%s->{'%s'}->[%d]), $self->{level}, $directive, $n);
                    $sub->{top}       = $self->{top};
                    $sub->{parent}    = $self;
                    $sub->{type}      = 'directive';
                    $sub->{name}      = $directive;
                    $sub->{value}     = $root->{$directive}->[$n]->[0];
                    $sub->{to_string} = $sub->{value};

                    # with new api, we have to return the last element in scalar context like normal
                    # list in scalar context. So we don't bless all unwanted objects instances.
                    return $sub if(!$self->{oldapi} && !wantarray);
                        
                    $directive_values[$n] = $sub;
                }
                return(wantarray ? @directive_values : ($self->{oldapi} ? \@directive_values : @directive_values)); 
                                                       # ascendant compatibility 
            }
            else
            {
                # called like this: $obj->directive(Foo, -which=>n)
                if($root->{$directive}->[$which])
                {
                    my $sub = bless({});
                    $sub->{level}     = sprintf(q(%s->{'%s'}->[%d]), $self->{level}, $directive, $which);
                    $sub->{top}       = $self->{top};
                    $sub->{parent}    = $self;
                    $sub->{type}      = 'directive';
                    $sub->{name}      = $directive;
                    $sub->{value}     = $root->{$directive}->[$which]->[0];
                    $sub->{to_string} = $sub->{value};
                    return($sub);
                }
                else
                {
                    return undef;
                }
            }
        }
    }
    else
    {
        if($which eq '')
        {
            # called like this: $obj->directive

            my @directives;
            foreach(_get_directives($root))
            {
                my $directive  = $_->[0];
                my $value      = $_->[1];
                my $this_which = $_->[3];
                my $sub = bless({});
                $sub->{level}     = sprintf(q(%s->{'%s'}->[%d]), $self->{level}, $directive, $this_which);
                $sub->{top}       = $self->{top};
                $sub->{parent}    = $self;
                $sub->{type}      = 'directive';
                $sub->{name}      = $directive;
                $sub->{value}     = $value;
                $sub->{to_string} = _untype($sub->{name}, 'directive');

                # with new api, we have to return the last element in scalar context like normal
                # list in scalar context. So we don't bless all unwanted objects instances.
                return $sub if(!$self->{oldapi} && !wantarray);

                push(@directives, $sub);
            }
            return(wantarray ? @directives : ($self->{oldapi} ? \@directives : @directives));
        }
        else
        {
            # called like this: $obj->directive(-which=>n)

            my @directives = _get_directives($root);
            if(defined $directives[$which])
            {
                my $directive  = $directives[$which]->[0];
                my $value      = $directives[$which]->[1];
                my $this_which = $directives[$which]->[3];
                my $sub = bless({});
                $sub->{level}     = sprintf(q(%s->{'%s'}->[%d]), $self->{level}, $directive, $this_which);
                $sub->{top}       = $self->{top};
                $sub->{parent}    = $self;
                $sub->{type}      = 'directive';
                $sub->{name}      = $directive;
                $sub->{value}     = $value;
                $sub->{to_string} = _untype($sub->{name}, 'directive');

                return $sub;
            }
            else
            {
                return $self->_set_error('directive doesn\'t exists');
            }
        }
    }
}

=pod

=head2 delete ()

    $htconf->directive('AddType'=>'.pl')->delete;
    $htconf->section('File'=>'/path/to/file')->delete;

Delete the current context pointed by object. Can be directive or section.

=cut

sub delete
{
    my $self    = shift;
    my $root    = $self->_root || return undef;
    my $top     = $self->{top};
    my $deleted = 0;

    if($self->{type} eq 'section')
    {
        my $lines   = $root->{_pos};
        for(my $i = 0; $i < @$lines; $i++)
        {
            my $offset = $lines->[$i]->[0]; # first section opener tag's line (for trucated line) 
            my $length = $lines->[++$i]->[-1] - $offset + 1; # last section closer tag's line (for trucated line)
            $offset -= $deleted;
            $self->_delete_line($offset+1, $length);
            $deleted += $length;
        }
    }
    elsif($self->{type} eq 'directive')
    {
        my $offset = $root->[1]->[0];
        my $length = $root->[1]->[-1] - $offset + 1;
        $self->_delete_line($offset+1, $length);
        $deleted = $length;
    }
    else
    {
        return($self->_set_error('method not allowed'));
    }

    return($deleted);
}

=pod

=head2 set_value (I<newvalue>)

    $htconf->directive('File'=>'/path/to/foo')->set_value('/path/to/bar');

Change the value of a directive or section. If no argument given, return
the value of object $htconf.

=head2 value ()

Return the value of rule pointed by the object if any.

(C<value> and C<set_value> are the same method)

=cut

*set_value = \&value;

sub value
{
    my $self     = shift;
    my $newvalue = shift || return $self->{value};
    my $top      = $self->{top};
    my $root     = $self->_root or return undef;
    my $type     = $self->type;
    
    if($type eq 'section')
    {
        my $offset = $root->{_pos}->[0]->[0];
        my $length = $root->{_pos}->[0]->[-1] - $offset + 1;
        print "lkjdsflkj $offset\n";
        splice(@{$top->{contents_raw}}, $offset, $length, $self->write_section($self->name, $newvalue));
        $self->_refresh_pos($offset + 1, $length - 1) if($length > 1);
    }
    elsif($type eq 'directive')
    {
        my $offset = $root->[1]->[0];
        my $length = $root->[1]->[-1] - $offset + 1;
        splice(@{$top->{contents_raw}}, $offset, $length, $self->write_directive($self->name, $newvalue));
        $self->_refresh_pos($offset + 1, $length - 1) if($length > 1);
    }
    else
    {
        return($self->_set_error('method not allowed'));
    }

    return($newvalue);
}

=pod

=head2 move (B<-before>=>I<target> | B<-after>=>I<target> | B<-replace>=>I<target> | B<-tofirst> | B<-tolast>)

under construction

=cut

sub move
{
    my $self = shift;
    return $self->_set_error('method not allowed') if($self->{type} eq 'top');

    
}

=pod

=head2 name ()

Return the name of the current pointed directive or section. return undef if object point
to the top context:

    my $obj = new Apache:Admin::Config ("/path/to/file");

    $obj->name; return undef
    $obj->directive(-which=>0)->name; return first directive's name
    $obj->section(Foo, -which=>0)->name; return "Foo"

=cut

sub name
{
    my $self = shift;
    my $type = $self->type;
    return($type ne 'top' ? _untype($self->{name}, $type) : $self->_set_error('method not allowed'));
}

=pod

=head2 lines ()

=over 2

=item *

If the caller object point to a directive :

Return a list of lines'number occuped by the object's directive. If more
than one line'number is return, that's mean the directive is truncated on
serveral lines :

    18. DirectoryIndex  index.html \
    19.                 index.shtml \
    20.                 index.pl \
    ...

    $obj->directive(DirectoryIndex, -which=>x)->line # return (18, 19, 20)

=item *

If the caller object point to a section :

Return a list of arrayref where all odd indexes are sections-opening and pair
are sections-closing. Each arrayref conteints a list of lines'number occuped
by the section rule (if section rule truncated).

    18. <VirtualHost 127.0.0.1 \
    19.              10.20.30.40 \
    20.              197.200.30.40>
    21.     ServerName example.com
    22. </VirtualHost>
    ...
    50. <VirtualHost 127.0.0.1 10.20.30.40 197.200.30.40>
    51.     ServerAlias www.example.com
    52.     User        rs
    53. </VirtualHost>

    $obj->directive(VirtualHost, -which=>x)->lines # return ([18, 19, 20], [22], [50], [53])

=back

=cut

sub lines
{
    my $self = shift;
    my $type = $self->type;
    return($self->_set_error('method not allowed')) if($type eq 'top');
    my $root = $self->_root or return undef;

    if($type eq 'directive')
    {
        return(map($_+1, @{$root->[1]}));
    }
    elsif($type eq 'section')
    {
        return(map([map($_+1, @$_)], @{$root->{_pos}}));
    }
}

=pod

=head2 first_line ()

=cut

sub first_line
{
    my $self = shift;
    my $type = $self->type;
    my $root = $self->_root or return undef;

    if($type eq 'top')
    {
        return 1; # first line of file is always 1
    }
    elsif($type eq 'directive')
    {
        return($root->[1]->[0]+1);
    }
    elsif($type eq 'section')
    {
        return($root->{_pos}->[0]->[0]+1);
    }
}

=pod

=head2 last_line ()

=cut

sub last_line
{
    my $self = shift;
    my $type = $self->type;
    my $root = $self->_root or return undef;

    if($type eq 'top')
    {
        return(scalar(@{$self->{top}->{contents_raw}})); # first line of file is always 1
    }
    elsif($type eq 'directive')
    {
        return($root->[1]->[-1]+1);
    }
    elsif($type eq 'section')
    {
        return($root->{_pos}->[-1]->[-1]+1);
    }
}

=pod

=head2 dump_line I<line_number>

    $obj->dump_line($directive->first_line);

Dump the I<line_number> line of current parsed configuration.

=cut

sub dump_line
{
    my $self        = shift;
    my $line_number = shift || return undef;

    return($self->{top}->{contents_raw}->[$line_number - 1]);
}

=pod

=head2 isin ($section_obj, [-recursif])

Return true if object point to a rule that is in the section represented by $section_obj. If
C<-recursif> option is present, true is also return if object is a sub-section of target.

    <section target>
        <sub section>
            directive test
        </sub>
    </section>

    $test_directive->isin($target_section)              => return false
    $test_directive->isin($sub_section)                 => return true
    $test_directive->isin($target_section, '-recursif') => return true

=cut

sub isin
{
    my $self     = shift;
    my $recursif = _get_arg(\@_, '-recursif!');
    my $target   = shift || return $self->_set_error('too few arguments');
    return($self->_set_error('method not allowed')) if($self->type eq 'top');
    return($self->_set_error('target is not an object of myself')) unless(ref $target && $target->isa(Apache::Admin::Config));
    return($self->_set_error('wrong type for target')) if($target->type eq 'directive');

    if($recursif)
    {
        return(1) if($target->type eq 'top');
        return(index($target->{level}, $self->parent->{level}) == 0);

#         my @lines  = $target->lines;
#         my $line   = $self->first_line;
#         print "line=$line, lines=", join(' ', map($_->[0], @lines)),"\n";
#         return($self->_set_error('unexpected error, bad number of lines for target')) if(@lines % 2);
#         for(my $i = 0; $i <= @lines; $i+=2)
#         {
#             return 1 if($line > $lines[$i]->[0] && $line < $lines[$i+1]->[0]);
#         }
    }
    else
    {
        return($self->parent->{level} eq $target->{level})
    }

    return 0;
}

=pod

=head2 parent ()

Return the parent context of object.

$obj is same as $obj->directive(-which=>0)->parent

=cut

sub parent
{
    $_[0]->{parent};
}

=pod

=head2 type ()

Return the type of object. Types can be 'directive', 'section' or 'top'.

=cut

sub type
{
    $_[0]->{type};
}

# used for overload => ""
sub to_string
{
    my($self, $other, $inv, $meth) = @_;
    return overload::StrVal($self) unless defined $self->{to_string};

    if($meth eq 'eq')       { return($other ne $self->{to_string}); }
    elsif($meth eq 'ne')    { return($other ne $self->{to_string}); }

    return $self->{to_string};
}

=pod

=head2 error ()

Return the last append error.

=cut

sub error
{
    return $_[0]->{top}->{__last_error__};
}

sub _root
{
    my $self = shift;
    
    my $root;
    eval('$root=$self->{top}->{contents_parsed}'.$self->{level});
    return($self->_set_error('can\'t get root')) unless(defined $root && ref $root);
    return($root);
}

sub _type
{
    my($name, $type, $value, $which) = @_;
    my $tag = uc(substr($type, 0, 1));
    if($tag eq 'S')
    {
        $which ||= 1;
        $tag .= $which.':'.$name.'='.$value;
    }
    else
    {
        $tag .= ":$name";
    }
    return $tag;
}

sub _untype
{
    my($name, $type) = @_;
    $type = uc(substr($type, 0, 1));
    if(index($name, $type) == 0)
    {
        my $value = substr($name, index($name, ':')+1, length $name);
        return $type eq 'S' ? (split(/=/, $value, 2))[0] : $value;
    }
    else
    {
        warn("_untype failed at line ", (caller)[2]);
        return(undef);
    }
}

sub _delete_line
{
    my($self, $line, $howmany) = @_;
    return $self->_set_error('bad line number')
        unless($line !~ /[^\d\-]/);
    my $index = ($line > 0 ? $line - 1 : $line);
    splice(@{$self->{top}->{contents_raw}}, $index, $howmany);
    $self->_refresh_pos($index, $howmany*-1);
}

sub _insert_line
{
    # insert a new line in the file, and reparse it
    # syntax: $self->_insert_line(line_number, rule1, rule2, rule3...)
    my $self  = shift;
    my $line  = $_[0] !~ /[^\d\-]/ ? shift : return $self->_set_error('bad line number');

    my $index = ($line > 0 ? $line - 1 : $line);
    splice(@{$self->{top}->{contents_raw}}, $index, 0, @_);

    $self->_refresh_pos($index, scalar @_)
}

sub _refresh_pos
{
    my($self, $index, $count, $tree) = @_;
    $tree = $self->{top}->{contents_parsed}
        unless defined $tree;

    foreach(keys %$tree)
    {
        if(index($_, 'D') == 0)
        {
            foreach my $ary (@{$tree->{$_}})
            {
                foreach(@{$ary->[1]})
                {
                    $_ += $count if($_ >= $index);
                }
            }
        }
        elsif(index($_, 'S') == 0)
        {
            $self->_refresh_pos($index, $count, $tree->{$_});
        }
        elsif($_ eq '_pos')
        {
            foreach $ary (@{$tree->{$_}})
            {
                foreach(@$ary)
                {
                    $_ += $count if($_ >= $index);
                }
            }
        }
    }
}

sub _insert_directive
{
    my($tree, $directive, $value, $pos) = @_;

    # we add a D in front of directive for isolate it from sections
    $directive = _type(lc($directive), 'directive');
    $value = defined $value ? $value : '';
    $value =~ s/^\s+|\s+$//g;

    push(@{$tree->{$directive}}, [$value, $pos]); #[value, line's position]
}

sub _insert_section
{
    my($tree, $section, $value, $pos) = @_;

    # increment the section counter of same name on same level, used for
    # select which homonyme section we talk about
    my $which = ++$tree->{_sections_counter}->{$section};
    # we add an S in front of section for isolate it from directives 
    # (followed by the section counter for isolate same named sections)
    $value = defined $value ? $value : '';
    $value =~ s/^\s+|\s+$//g;
    $section = _type(lc($section), 'section', $value, $which);

    $tree->{$section} ||= {};
    # save the line number of this section
    push(@{$tree->{$section}->{_pos}}, $pos);
    return $tree->{$section};
}

sub _insert_section_closer
{
    my($tree, $pos) = @_;
    push(@{$tree->{_pos}}, $pos); # save last line of section
}

# this function returns an array of arrayref. each arrayref contents
# 0 = typed directive name (with the D: identifier on front)
# 1 = value
# 2 = arrayref off lines position
# 3 = index of same name directives
sub _get_directives
{
    my($tree) = @_;
    
    my @directives;
    foreach(keys %$tree)
    {
        if(index($_, 'D') == 0)
        {
            my $directive = $_;
            my $which = 0;
            foreach(@{$tree->{$_}})
            {
                push(@directives, [$directive, @$_, $which++]);
            }
        }
    }
    return sort {$a->[2]->[0] <=> $b->[2]->[0]} @directives;
}

sub _get_sections
{
    my($tree) = @_;

    my @sections;
    foreach(keys %$tree)
    {
        if(index($_, 'S') == 0)
        {
            my $section = $_;
            my $secname = _untype($section, 'section');
            my $value = (split(/=/, $section, 2))[1];
            push(@sections, [$section, $value, $tree->{$section}->{_pos}, $secname]);
        }
    }

    my %same;

    # sorting section on first line number of section openner and feed the 3th element
    # of array: the same section named index
    @sections = sort {$a->[2]->[0]->[0] <=> $b->[2]->[0]->[0]} @sections;
    foreach(@sections)
    {
        $_->[3] = $same{$_->[3]}++ || 0;
    }
    return @sections;
}

sub _parse
{
    my $self = shift;
    my $file = $self->{htaccess} || '[inline]';
    my @htaccess = @{$self->{top}->{contents_raw}};

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
        _clear_double_spaces($line);
        if($line =~ /^(\w+)\s*(.*)$/)
        {
            # it's a directive
            _insert_directive($level[-1], $1, $2, \@_pos);
        }
        elsif($line =~ /^<\s*(\w+)(?:\s+([^>]+)|\s*)>$/)
        {
            # it's a section opening
            my $section_name = lc $1;
            my $section = _insert_section($level[-1], $section_name, $2, \@_pos);
            push(@level, $section);
            push(@last_section, $section_name);
        }
        elsif($line =~ /^<\/\s*(\w+)\s*>$/)
        {
            # it's a section closing
            my $section_name = lc $1;
            return $self->_set_error(sprintf('%s: syntax error at line %d', $file, $n+1)) 
              if(!@last_section || $section_name ne $last_section[-1]);
            _insert_section_closer($level[-1], \@_pos);
            pop(@last_section);
            pop(@level);
        }
        else
        {
            return $self->_set_error(sprintf('%s: syntax error at line %d', $file, $n+1));
        }
    }

    eval('use Data::Dumper; print Data::Dumper::Dumper(\%contents_parsed), "\n";') if($Apache::Admin::Config::DEBUG);

    $self->{top}->{contents_parsed} = \%contents_parsed;

    return 1;
}

sub _get_arg
{
    my($args, $motif) = @_;
    # motif is a list of searched argument separated by a pipe
    # each arguments can be ended by a ! for specifing that it don't wait for a value
    # (ex: "-arg1|-arg2!" here -arg2 is boolean)
    # return (value, argname)

    return '' unless(@$args);
    for(my $n = 0; $n < @$args; $n++)
    {
        foreach my $name (split(/\|/, $motif))
        {
            my $boolean = ($name =~ s/\!$//);
            if(defined $args->[$n] && !ref($args->[$n]) && $args->[$n] eq $name)
            {
                return(undef) if(!$boolean && $n+1 >= @$args); # malformed argument
                my $value = splice(@$args, $n, ($boolean?1:2));
                $value = '' unless defined $value;
                return(wantarray ? ($value, $name) : $value); # suppres argument name and its value from the arglist and return the value
            }
        }
    }
    return '';
}

sub _init
{
    my $self = shift;
    $self->{top}->{contents_raw} = [];
    return $self->_parse;
}

sub _load
{
    my $self = shift;
    my $htaccess = $self->{htaccess};
    my @htaccess;
    my $fh;

    if(ref $htaccess eq 'GLOB')
    {
        $fh = $htaccess;
    }
    else
    {
        return $self->_set_error("`$htaccess' not readable") unless(-r $htaccess);
        $fh = new FileHandle($htaccess) or return $self->_set_error("can't open `$htaccess' file for reading");
    }
    
    while(<$fh>)
    {
        chomp;
        push(@htaccess, $_);
    }

    $self->{top}->{contents_raw} = \@htaccess;
    return $self->_parse;
}

sub _set_error
{
    my $self = shift;
    $Apache::Admin::Config::ERROR = $self->{top}->{__last_error__} = join('', (caller())[0].': ', @_);
    return;
}

sub _clear_double_spaces
{
    # TODO remove all double spaces excepted quoted spaces
}

DESTROY
{
    undef($_[0]->{top});
}

1;

=pod

=head1 EXAMPLES

    #
    # Managing virtual-hosts:
    #
    
    my $conf = new Apache::Admin::Config "/etc/apache/httpd.conf";

    # adding a new virtual-host:
    my $vhost = $conf->add_section(VirtualHost=>'127.0.0.1');
    $vhost->add_directive(ServerAdmin=>'webmaster@localhost.localdomain');
    $vhost->add_directive(DocumentRoot=>'/usr/share/www');
    $vhost->add_directive(ServerName=>'www.localhost.localdomain');
    $vhost->add_directive(ErrorLog=>'/var/log/apache/www-error.log');
    my $location = $vhost->add_section(Location=>'/admin');
    $location->add_directive(AuthType=>'basic');
    $location->add_directive(Require=>'group admin');
    $conf->save;

    # selecting a virtual-host:
    my $vhost;
    foreach my $vh (@{$conf->section('VirtualHost')})
    {
        if($vh->directive('ServerName')->value eq 'www.localhost.localdomain')
        {
            $vhost = $vh;
            last;
        }
    }

=head1 AUTHOR

Olivier Poitrey E<lt>rs@rhapsodyk.netE<gt>

=head1 AVAILABILITY

The official FTP location is:

B<ftp://ftp.rhapsodyk.net/pub/devel/perl/Apache-Admin-Config-current.tar.gz>

Also available on CPAN.

anonymous CVS repository:

CVS_RSH=ssh cvs -d anonymous@cvs.rhapsodyk.net:/devel co Apache-Admin-Config

(supply an empty string as password)

CVS repository on the web:

http://www.rhapsodyk.net/cgi-bin/cvsweb/Apache-Admin-Config/

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
