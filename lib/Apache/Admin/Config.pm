package Apache::Admin::Config;

use 5.005;
use strict;
use FileHandle;

$Apache::Admin::Config::VERSION = '0.54';
$Apache::Admin::Config::DEBUG   = 0;

=pod

=head1 NAME

Apache::Admin::Config - A common module to manipulate Apache configuration files

=head1 SYNOPSIS

    use Apache::Admin::Config;

    # Parse an apache configuration file

    my $conf = new Apache::Admin::Config "/path/to/config_file.conf"
        or die $Apache::Admin::Config::ERROR;


    # or parse a filehandle

    open(ANHANDLE, "/path/to/a/file")...

    my $conf = new Apache::Admin::Config \*ANHANDLE
        or die $Apache::Admin::Config::ERROR;

    ...

    # Directive method called without any argument, return a list
    # of all directive located in the current context.

    my @directives_list = $conf->directive;

    # This method returns a list of object (one object by directive)
    # sorted by order of apparence in the file.

    # You can easly get the 3th directive of the context

    my $directive = $directives_list[2];

    # or

    my $directive = $conf->directive(-which=>2);
    

    # Then, you can manipulate object like this

    if(defined $directive)
    {
        print $directive->name;   # "documentroot"
        print $directive->value;  # "/my/document/root"
        print $directive->type;   # "directive"
        $directive->isin($conf);  # true
        ...
        $directive->delete;
    }

    
    # this print all current context's directives names

    foreach($conf->directive)
    {
        print $_->name, "\n";
    }
    
    # You want get all directives of current context who's name is "Foo",
    # juste give the string "Foo" at first argument to methode `directive' :
    
    my @foo_directives = $obj->directive('Foo');

    # or just the 4th

    my $4th_foo_directive = $obj->directive('Foo', -which=>4);


    # you may want all directives named "Foo" but with value "Bar", so
    # give the wanted value as second argument to `directive' :
    
    my @foo_bar_directives = $conf->directive(Foo=>'Bar');

    # or just the last one in scalar context

    my $foo_bar_directive = $conf->directive(Foo=>'Bar');

    # or the second one if "-which" option is given.

    my $foo_bar_directive = $conf->directive(Foo=>'Bar', -which=>2);


    # Working on directive "PidFile" :
    #
    # getting the last pidfile directive

    my $pidfile = $conf->directive('PidFile');
    
    # changing its value to '/var/run/apache.pid'

    my $pidfile_value = '/var/run/apache.pid';

    if(defined $pidfile)
    {
        $pidfile->set_value($pidfile_value)
            unless $pidfile->value eq $pidfile_value;
    }
    else
    {
        $conf->add_directive(PidFile => $pidfile_value);
    }


    # Deleting all directives "AddType"

    foreach($conf->directive(AddType))
    {
        $_->delete;
    }


    # Adding directive "AddType text/html .shtml" just after the last AddType directive if any
    # or at the end of file (or section)

    my $last_addtype = $obj->directive('AddType', -which=>-1);

    if(defined $last_addtype)
    {
        $conf->add_directive(AddType => 'text/html .shtml', -after=>$last_addtype);
    }
    else
    {
        $conf->add_directive(AddType => 'text/html .shtml', '-bottom');
    }

    # You can get a directive located in a section like this

    my $section = $conf->section(Foo=>'Bar');
    my $subdirective;
    if(defined $section)
    {
        $subdirective = $section->directive(Bar=>'foo');
    }

    # saving changes in place

    $conf->save;
    
    # or in another file (sound like "save as...")

    $conf->save("/path/to/another/file");

    # or in an already openned file

    $conf->save(\*FILE_HANDLE);

=head1 DESCRIPTION

C<Apache::Admin::Config> provides an object interface to handling Apache like
configuration files without modifying comments, identation, or truncated lines.

=head1 METHODES

=head2 NEW

    $obj = new Apache::Admin::Config [/path/to/file|handle], [-indent => $integer]

Create or read, if given in argument, an apache like configuration file, and
return an Apache::Admin::Config instence.

Arguments:

=over 4

=item I<C</path/to/file>>

Path to the configuration file to parse. If none given, create a new one.

=item I<C<handle>>

Instead of specify a path to a file, you can give a reference to an handle that
point to an already openned file. You can do this like this :

    my $obj = new Apache::Admin::Config (\*MYHANDLE);

=item I<B<-indent>> =E<gt> I<$integer>

If greater than 0, activates the indentation on added lines, the integer tell how
many spaces you went per level of indentation (suggest 4). A negative value means
padding with tabulation(s).

=back

=cut

# We wrap the whole module part because we manipulate a tree with circular
# references. Because of the way perl's garbage collector works, we have to
# isolate circular reference in another package to be able to destroy circular
# reference before the garbage collector try to destroy the tree.
# Without this mechanism, the DESTROY event will never be called.

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self  = {};
    bless $self, $class;

    my $htaccess = shift;
    my $tree = $self->{tree} = new Apache::Admin::Config::Tree(@_)
        or return;

    if(defined $htaccess && (ref $htaccess eq 'GLOB' || -f $htaccess)) # trying to handle GLOBs
    {
        $tree->_load($htaccess) || return undef;
    }
    else # if htaccess doesn't exists, init new one
    {
        $tree->_init || return undef;
    }
 
    return $self;
}

=pod

=head2 SAVE

    $obj->save([/path/to/file|HANDLE])

Write modifications to the configuration file. If a path to a file is given,
save the modification to this file instead. You also can give a reference to
a filehandle like this :

    $conf->save(\*MYHANDLE) or die($conf->error);

=cut

sub save
{
    my($self, $saveas) = @_;

    my $htaccess = defined $saveas ? $saveas : $self->{tree}->{htaccess};

    return $self->_set_error("you have to specify a location for writing configuration")
        unless defined $htaccess;

    my $fh;

    if(ref $htaccess eq 'GLOB')
    {
        $fh = $htaccess;
    }
    else
    {
        $fh = new FileHandle(">$htaccess")
            or return $self->_set_error("can't open `$htaccess' file for read");
    }

    print $fh $self->dump_raw;

    return 1;
}



sub AUTOLOAD
{
    # redirect all method to the right package
    my $self  = shift;
    my($func) = $Apache::Admin::Config::AUTOLOAD =~ /[^:]+$/g;
    return $self->{tree}->$func(@_);
}

sub DESTROY
{
    shift->{tree}->destroy;
}

package Apache::Admin::Config::Tree;

use strict;
use Carp;
use FileHandle;
use overload nomethod => \&to_string;


sub new 
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self  = {};
    bless($self, $class);

    $self->{indent} = _get_arg(\@_, '-indent');

    # init the tree
    $self->{top}     = $self;
    $self->{type}    = 'section';
    $self->{parent}  = undef;
    $self->{children}  = [];
   
    return($self);
}

=pod

=head2 DUMP_RAW

    $obj->dump_raw

Returns the configuration file as same as it will be if it saved in a file with
the B<save()> method. If you don't call this method from the top level section,
it returns the part of the configuration file that is under the object's context.

=cut

sub dump_raw
{
    my($self) = @_;
    return _deploy($self);
}

=pod

=head2 SELECT

    $obj->select
    (
        [-type  => $type],
        [-name  => $name],
        [-value => $value],
        [-which => $index],
    );

    @directives    = $obj->select('directive');
    @sections_foo  = $obj->select('section', 'Foo');

This method search in the current context for items (directives, sections,
comments...) that correspond to a properties given by arguments. It returns
a B<list> of matched objects.

This method can only be called on an object of type "section". This method search
only for elements in the section pointed by object, and isn't recursive. So elements
B<in> sub-sections of current section aren's seek.

Arguments:

=over 4

=item B<C<type>>

The type of searched item.

=item B<C<name>>

The name of item.

=item B<C<value>>

Value of item.

=item B<C<which>>

Instead of returns a list of objects, returns only ones pointed
by index given to the -which option. Caution, returns an empty
string if none selected, so don't cascade your methodes calls 
like $obj->select(-which=>0)->name.

=back

Method returns a list of object(s) founds.

=cut

sub select
{
    my $self = shift;

    my $which = _get_arg(\@_, '-which');

    my %args;
    $args{type}  = _get_arg(\@_, '-type')  || undef;
    $args{name}  = _get_arg(\@_, '-name')  || undef;
    $args{value} = _get_arg(\@_, '-value') || undef;

    # accepting old style arguments for backward compatibilitie
    $args{type}  = shift unless defined $args{type};
    $args{name}  = shift unless defined $args{name};
    $args{value} = shift unless defined $args{value};

    # _get_arg return undef on error or empty string on not founded rule
    return $self->_set_error('malformed arguments')
        if not defined $which; 
    # $which isn't an integer
    return $self->_set_error('error in -which argument: not an integer')
        if $which =~ /[^\d\-]/;
    return $self->_set_error('too many arguments')
        if @_;
    return $self->_set_error('method not allowed')
        unless $self->{type} eq 'section';

    $args{name} = lc $args{name} if defined $args{name};

    my @children = @{$self->{children}};

    my $n = 0;
    my @items;
    # pre-select fields to test on each objects
    my @field_to_test = 
        grep(defined $args{$_}, qw(type name value));

    foreach my $item (@children)
    {
        my $match = 1;
        # for all given arguments, we test if it matched
        # for missing aguments, match is always true
        foreach(@field_to_test)
        {
            # an error occurend, we want select object
            # on a properties that it doesn't have
            return length $which ? '' : ()
                unless(defined $item->{$_});

            $match = $args{$_} eq $item->{$_};

            last unless $match;
        }

        if($match)
        {
            push(@items, $item);
        }
    }

    if(length $which)
    {
        return defined overload::StrVal($items[$which]) ? $items[$which] : '';
    }
    else
    {
        # We don't return just @items but transfort it in a list because
        # in scalar context, returning an array is same as returning the number
        # of ellements in it, but we want return the _last_ element like a list
        # do une scalar context. If you have a better/nicer idea...
        return(@items ? @items[0 .. $#items] : ());
    }
}

=pod

=head2 DIRECTIVE

    $obj->directive(args...)

Same as calling select('directive', args...)

=cut

sub directive
{
    my $self = shift;
    $self->select('directive', @_);
}

=pod

=head2 SECTION

    $obj->section(args...)

Same as calling select('section', args...)

=cut

sub section
{
    my $self = shift;
    $self->select('section', @_);
}

=pod

=head2 COMMENT

    $obj->comment(args...)

Same as calling select('comment', args...)

=cut

sub comment
{
    my $self = shift;
    $self->select('comment', undef, @_);
}

=pod

=head2 BLANK

    $obj->blank(args...)

Same as calling select('blank', args...)

=cut

sub blank
{
    my $self = shift;
    $self->select('blank', @_);
}



sub write_directive
{
    # this methode is made for easy directive writing's overload
    my($self, $name, $value) = @_;
    return undef unless defined $name;
    $value = defined $value ? $value : '';
    my $indent = '';
    return($self->_indent."$name $value\n");
}

sub write_section
{
    # this methode is made for easy sections writing's overload
    # must take 2 arguments (directive name, directive value)
    # and return a string
    my($self, $name, $value) = @_;
    return($self->_indent."<$name $value>\n");
}

sub write_section_closing
{
    # this methode is made for easy sections closer writing's overload
    # take 1 argument (directive name) and return string
    my($self, $name) = @_;
    return($self->_indent."</$name>\n");
}

sub write_comment
{
    my($self, $value) = @_;
    $value =~ s/\n//g;
    return "# $value\n";
}

=pod

=head2 ADD

    $obj->add
    (
        $type, [$name], [$value],
        [-before => $target | -after => $target | '-ontop' | '-onbottom']
    );

    $obj->add('section', foo => 'bar', -after => $conf_item_object);
    $obj->add('comment', 'a simple comment', '-ontop');

Add a line of type I<$type> with name I<foo> and value I<bar> in the context pointed by B<$object>.

Aguments:

=over 4

=item B<C<type>>

Type of object to add (directive, section, comment or blank)

=item B<C<name>>

Only relevant for directives and sections.

=item B<C<value>>

For directive and section, it defines the value, for comments it
defined the text.

=item B<C<-before>> =E<gt> I<target>

Inserts item one line before I<target>. I<target> _have_ to be in the same context

=item B<C<-after>> =E<gt> I<target>

Inserts item one line after I<target>. I<target> _have_ to be in the same context

=item B<C<-ontop>>

Insert item on the fist line of current context;

=item B<C<-onbottom>>

Iinsert item on the last line of current context;

=back

Returns the added item

=cut

sub add
{
    my $self = shift;

    my($target, $where) = _get_arg(\@_, '-before|-after|-ontop!|-onbottom!');
    
    $target = $target->{tree} if ref $target eq 'Apache::Admin::Config';

    # _get_arg return undef on error or empty string on not founded rule
    return($self->_set_error('malformed arguments'))
        if(not defined $target);
    return($self->_set_error('too many arguments'))
        if(@_ > 3);
    my($type, $name, $value) = @_;

    return($self->_set_error('method not allowed'))
        unless($self->{type} eq 'section');

    $where = defined $where ? $where : '-onbottom'; # default behavior
    if(($where eq '-before' || $where eq '-after') && defined $target)
    {
        return $self->_set_error("target `$target' isn\'t an object")
            unless ref $target && $target->isa('Apache::Admin::Config::Tree');
        return $self->_set_error('invalid target context')
            unless $target->isin($self);
    }

    my $index;

    if($where eq '-before')
    {
        $index = $target->_get_index;
    }
    elsif($where eq '-after')
    {
        $index = $target->_get_index + 1;
    }
    elsif($where eq '-ontop')
    {
        $index = 0;
    }
    elsif($where eq '-onbottom' || $where eq '')
    {
        $index = -1;
    }
    else
    {
        return $self->_set_error('malformed arguments');
    }

    my $item;

    if($type eq 'section')
    {
        return $self->_set_error('to few arguments')
            unless(defined $name and defined $value);
        my $raw = $self->write_section($name, $value);
        my $length = () = $raw =~ /\n/g;
        $item = $self->_insert_section($name, $value, $raw, $length, $index);
        $item->{raw2} = $self->write_section_closing($name);
        $item->{length2} = () = $item->{raw2} =~ /\n/g;
    }
    elsif($type eq 'directive')
    {
        return $self->_set_error('to few arguments')
            unless(defined $name);
        my $raw = $self->write_directive($name, $value);
        my $length = () = $raw =~ /\n/g;
        $item = $self->_insert_directive($name, $value, $raw, $length, $index);
    }
    elsif($type eq 'comment')
    {
        # $name contents value here
        return $self->_set_error('to few arguments')
            unless(defined $name);
        $item = $self->_insert_comment($name,
                    $self->write_comment($name), $index);
    }
    elsif($type eq 'blank')
    {
        $item = $self->_insert_blank('', $index);
    }
    else
    {
        return $self->_set_error("invalid type `$type'");
    }

    return $item;
}

=pod

=head2 ADD_SECTION

    $obj->add_section(args...)

Same as calling add('section', args...)

=cut

sub add_section
{
    my $self = shift;
    return $self->add('section', @_);
}

=pod

=head2 ADD_DIRECTIVE

    $obj->add_directive(args...)

Same as calling add('directive', args...)

=cut

sub add_directive
{
    my $self = shift;
    return $self->add('directive', @_);
}

=pod

=head2 ADD_COMMENT

    $obj->add_comment(args...)

Same as calling add('comment', args...)

=cut

sub add_comment
{
    my $self = shift;
    return $self->add('comment', @_);
}

=pod

=head2 ADD_BLANK

    $obj->add_blank(args...)

Same as calling add('blank', args...)

=cut

sub add_blank
{
    my $self = shift;
    return $self->add('blank', @_);
}

=pod

=head2 DELETE

    $item->delete;

Delete the current context pointed by object. Can be directive or section.

=cut

sub delete
{
    my($self) = @_;

    return $self->_set_error("can't delete top level section")
        unless defined $self->{parent};
    
    my $index = $self->_get_index;
    if(defined $index)
    {
        splice(@{$self->{parent}->{children}}, $index, 1);
        return 1;
    }
    return;
}

=pod

=head2 SET_VALUE

    $obj->set_value($newvalue)

Change the value of a directive or section. If no argument given, return
the value.

=head2 VALUE

Return the value of rule pointed by the object if any.

(C<value> and C<set_value> are the same method)

=cut

*set_value = \&value;

sub value
{
    my $self     = shift;
    my $newvalue = shift || return $self->{value};

    my $type     = $self->{type};
    
    if(grep($type eq $_, qw(section directive comment)))
    {
        $self->{raw} =~ s/$self->{value}/$newvalue/;
        $self->{value} = $newvalue;
    }
    else
    {
        return($self->_set_error('method not allowed'));
    }

    return($newvalue);
}

=pod

=head2 MOVE

    $obj->move
    (
        -before => target |
        -after => $target |
        -replace => $target |
        '-ontop' |
        '-onbottom'
    )

not yet implemented

=cut

sub move
{
    my $self = shift;
}

=pod

=head2 FIRST_LINE

=cut

sub first_line
{
    my($self) = @_;
    return ($self->{top}->_count_lines($self))[0];
}

=pod

=head2 LAST_LINE

=cut

sub last_line
{
    my($self) = @_;
    return ($self->{top}->_count_lines_last($self))[0];
}

=pod

=head2 ISIN

    $obj->($section_obj, ['-recursif'])

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
    $target = $target->{tree} if ref $target eq 'Apache::Admin::Config';
    return($self->_set_error('method not allowed'))
        unless(defined $self->{parent});
    return($self->_set_error('target is not an object of myself'))
        unless(ref $target && $target->isa('Apache::Admin::Config::Tree'));
    return($self->_set_error('wrong type for target'))
        unless($target->{type} eq 'section');

    if($recursif)
    {
        return(1) unless(defined $target->{parent});
        my $parent = $self->{parent};
        while($parent ne $target)
        {
            $parent = $self->{parent} || return;
        }
    }
    else
    {
        return(overload::StrVal($self->{parent}) eq overload::StrVal($target))
    }

    return 0;
}

sub to_string
{
    my($self, $other, $inv, $meth) = @_;

    if($meth eq 'eq')
    {
        if($^W and (!defined $other or !defined $self->{value}))
        {                                                                                
            carp "Use of uninitialized value in string eq";
        }   
        local $^W;
        return($other ne $self->{value});
    }   
    elsif($meth eq 'ne')                                                                 
    {
        if($^W and (!defined $other or !defined $self->{value}))
        {                                                                                
            carp "Use of uninitialized value in string ne";
        }   
        local $^W;
        return($other ne $self->{value});
    }   
    elsif($meth eq '==')
    {
        if($^W and (!defined $other or !defined $self->{value}))
        {
            carp "Use of uninitialized value in numeric eq (==)";
        }   
        local $^W;
        return($other != $self->{value});
    }   
    elsif($meth eq '!=')
    {
        if($^W and (!defined $other or !defined $self->{value}))
        {                                                       
            carp "Use of uninitialized value in numeric ne (!=)";
        }                                                        
        local $^W;
        return($other != $self->{value});
    }
    elsif(!defined $self->{value})
    {
        return overload::StrVal($self);
    }
    else
    {
        return $self->{value};
    }
}


=pod

=head2 NAME

Returns the name of the current pointed object if any

=head2 PARENT

Returns the parent context of object. This method on the top level object
returns C<undef>.

=head2 TYPE

Returns the type of object.

=cut

sub name
{
    return $_[0]->{name};
}
sub parent
{
    return $_[0]->{parent};
}
sub type
{
    return $_[0]->{type};
}

sub destroy
{
    my($self) = @_;
    delete $self->{top};
    delete $self->{parent};
    foreach(@{$self->{children}})
    {
        $_->destroy;
    }
}

=pod

=head2 ERROR

Return the last append error.

=cut

sub error
{
    return $_[0]->{top}->{__last_error__};
}

#
# Private methods
#

sub _indent
{
    my($self) = @_;
    my $parent = $self->parent;
    my $level = 0;
    my $indent = $self->{top}->{indent} || 0;
    while(defined $parent)
    {
        $parent = $parent->parent;
        $level++;
    }

    return($level 
        ? (($indent > 0 ? ' ' : "\t") x (abs $indent)) x $level
        : '');
}

sub _get_index
{
    my($self) = @_;
    return unless defined $self->{parent}; # if called by top node
    my @pchildren = @{$self->{parent}->{children}};
    for(my $i = 0; $i < @pchildren; $i++)
    {
        return $i if $pchildren[$i] eq $self;
    }
}

sub _deploy
{
    join '',
    map
    {
        if($_->{type} eq 'section')
        {
            ($_->{raw}, _deploy($_), $_->{raw2});
        }
        else
        {
            $_->{raw};
        }
    } @{$_[0]->{children}};
}

sub _count_lines
{
    my $c = $_[0]->{'length'} || 0;
    foreach my $i (@{$_[0]->{children}})
    {
        return($c+1, 1) if(overload::StrVal($_[1]) eq overload::StrVal($i));
        my($rv, $found) = _count_lines($i, $_[1]);
        $c += $rv;
        return($c, 1) if defined $found;
    }
    return $c + (defined $_[0]->{length2} ? $_[0]->{length2} : 0);
}

sub _count_lines_last
{
    my $c = $_[0]->{'length'};
    foreach my $i (@{$_[0]->{children}})
    {
        $c += _count_lines($i, $_[1]);
        return $c if($_[1] eq $i);
    }
    return $c + $_[0]->{length2};
}

sub _insert_directive
{
    my($tree, $directive_name, $value, $line, $length, $index) = @_;

    $value = defined $value ? $value : '';
    $value =~ s/^\s+|\s+$//g;

    my $directive = bless({});
    $directive->{type} = 'directive';
    $directive->{name} = lc($directive_name);
    $directive->{value} = $value;
    $directive->{parent} = $tree;
    $directive->{top} = $tree->{top};
    $directive->{raw} = $line;
    $directive->{'length'} = $length;

    if(defined $index && $index != -1)
    {
        splice(@{$tree->{children}}, $index, 0, $directive);
    }
    else
    {
        push(@{$tree->{children}}, $directive);
    }

    return $directive;
}

sub _insert_section
{
    my($tree, $section_name, $value, $line, $length, $index) = @_;

    $value = defined $value ? $value : '';
    $value =~ s/^\s+|\s+$//g;

    my $section = bless({});
    $section->{type} = 'section';
    $section->{name} = lc($section_name);
    $section->{value} = $value;
    $section->{parent} = $tree;
    $section->{children} = [];
    $section->{top} = $tree->{top};
    $section->{raw} = $line;
    $section->{'length'} = $length;

    if(defined $index && $index != -1)
    {
        splice(@{$tree->{children}}, $index, 0, $section);
    }
    else
    {
        push(@{$tree->{children}}, $section);
    }

    return $section;
}

sub _insert_comment
{
    my($tree, $value, $line, $index) = @_;

    my $comment = bless({});
    $comment->{type} = 'comment';
    $comment->{parent} = $tree;
    $comment->{value} = $value;
    $comment->{top} = $tree->{top};
    $comment->{raw} = $line;
    $comment->{'length'} = 1;

    if(defined $index && $index != -1)
    {
        splice(@{$tree->{children}}, $index, 0, $comment);
    }
    else
    {
        push(@{$tree->{children}}, $comment);
    }

    return $comment;
}

sub _insert_blank
{
    my($tree, $line, $index) = @_;

    my $blank = bless({});
    $blank->{type} = 'blank';
    $blank->{parent} = $tree;
    $blank->{top} = $tree->{top};
    $blank->{raw} = $line;
    $blank->{'length'} = 1;

    if(defined $index && $index != -1)
    {
        splice(@{$tree->{children}}, $index, 0, $blank);
    }
    else
    {
        push(@{$tree->{children}}, $blank);
    }

    return $blank;
}

sub _parse
{
    my($self, $fh) = @_;
    my $file = $self->{htaccess} || '[inline]';

    # level is used to stock reference to the curent level, level[0] is the root level
    my @level = ($self);
    my $line;
    my $n = 0;
    while((defined $fh) && ($line = scalar <$fh>) && (defined $line))
    {
        $n++;
        my $length = 1;

        while($line !~ /^\s*#/ && $line =~ s/\\$//)
        {
            # line is truncated, we want the entire line
            $n++;
            $line .= <$fh> 
                || return $self->_set_error(sprintf('%s: syntax error at line %d', $file, $n));
            $length++;
        }

        if($line =~ /^\s*#+\s*(.*?)\s*$/)
        {
            # it's a comment
            _insert_comment($level[-1], $1, $line);
        }
        elsif($line =~ /^\s*$/)
        {
            # it's a blank line
            _insert_blank($level[-1], $line);
        }
        elsif($line =~ /^\s*(\w+)(?:\s+(.*?)|)\s*$/)
        {
            # it's a directive
            _insert_directive($level[-1], $1, $2, $line, $length);
        }
        elsif($line =~ /^\s*<\s*(\w+)(?:\s+([^>]+)|\s*)>\s*$/)
        {
            # it's a section opening
            my $section = _insert_section($level[-1], $1, $2, $line, $length);
            push(@level, $section);
        }
        elsif($line =~ /^\s*<\/\s*(\w+)\s*>\s*$/)
        {
            # it's a section closing
            my $section_name = lc $1;
            return $self->_set_error(sprintf('%s: syntax error at line %d', $file, $n)) 
              if(!@level || $section_name ne $level[-1]->{name});
            $level[-1]->{raw2} = $line;
            $level[-1]->{length2} = $length;
            pop(@level);
        }
        else
        {
            return $self->_set_error(sprintf('%s: syntax error at line %d', $file, $n));
        }
    }

    eval('use Data::Dumper; print Data::Dumper::Dumper($self), "\n";') if($Apache::Admin::Config::DEBUG);

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
    return $self->_parse;
}

sub _load
{
    my($self, $htaccess) = @_;
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
    
    $self->{htaccess} = $htaccess;
    return $self->_parse($fh);
}

sub _set_error
{
    my $self = shift;
    $Apache::Admin::Config::ERROR = $self->{top}->{__last_error__} = join('', (caller())[0].': ', @_);
    return;
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

    #
    # Suppress all comments in the file
    # 

    sub delete_comments
    {
        foreach(shift->comment)
        {
            $_->delete;
        }
    }

    sub delete_all_comments
    {
        foreach($_[0]->section)
        {
            parse_all($_);
        }
        delete_comments($_[0]);
    }

    delete_all_comments($conf);


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

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=head1 COPYRIGHT

Copyright (C) 2001 - Olivier Poitrey
