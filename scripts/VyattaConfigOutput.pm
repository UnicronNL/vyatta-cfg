# Perl module for generating output of the configuration.
# 
# outputNewConfig()
#   prints the "new" config, i.e., the active config with any un-committed
#   changes. 'diff' notation is also generated to indicate the changes.
#
# outputActiveConfig()
#   prints the "active" config. suitable for "saving", for example.

package VyattaConfigOutput;

use strict;
use lib '/opt/vyatta/share/perl5/';
use VyattaConfig;

# whether to show default values
my $show_all = 0;
sub set_show_all {
  if (shift) {
    $show_all = 1;
  }
}

my $config = undef;

# $0: array ref for path
# $1: display prefix
# $2: node name
# $3: simple show (if defined, don't show diff prefix. used for "don't show as
#     deleted" from displayDeletedOrigChildren.)
sub displayValues {
  my @cur_path = @{$_[0]};
  my $prefix = $_[1];
  my $name = $_[2];
  my $simple_show = $_[3];
  my ($is_multi, $is_text, $default) = $config->parseTmpl(\@cur_path);
  $config->setLevel(join ' ', @cur_path);
  if ($is_multi) {
    my @ovals = $config->returnOrigValues('');
    my @nvals = $config->returnValues('');
    if ($is_text) {
      @ovals = map { "\"$_\""; } @ovals;
      @nvals = map { "\"$_\""; } @nvals;
    }
    my $idx = 0;
    my %ohash = map { $_ => ($idx++) } @ovals;
    $idx = 0;
    my %nhash = map { $_ => ($idx++) } @nvals;
    my @dlist = map { if (!defined($nhash{$_})) { $_; } else { undef; } }
                    @ovals;
    if (defined($simple_show)) {
      foreach my $oval (@ovals) {
        print "$prefix$name $oval\n";
      }
      return;
    }
    foreach my $del (@dlist) {
      if (defined($del)) {
        print "-$prefix$name $del\n";
      }
    }
    foreach my $nval (@nvals) {
      my $diff = '+';
      if (defined($ohash{$nval})) {
        if ($ohash{$nval} != $nhash{$nval}) {
          $diff = '>';
        } else {
          $diff = ' ';
        }
      }
      print "$diff$prefix$name $nval\n";
    }
  } else {
    my $oval = $config->returnOrigValue('');
    my $nval = $config->returnValue('');
    if ($is_text) {
      if (defined($oval)) {
        $oval = "\"$oval\"";
      }
      if (defined($nval)) {
        $nval = "\"$nval\"";
      }
    }
    if (defined($simple_show)) {
      if (!defined($default) || $default ne $oval || $show_all) {
        print "$prefix$name: $oval\n";
      }
      return;
    }
    my $value = $nval;
    my $diff = ' ';
    if (!defined($oval) && defined($nval)) {
      $diff = '+';
    } elsif (!defined($nval) && defined($oval)) {
      $diff = '-';
      $value = $oval;
    } else {
      # both must be defined
      if ($oval ne $nval) {
        $diff = '>';
      }
    }
    if (!defined($default) || $default ne $value || $show_all) {
      print "$diff$prefix$name: $value\n";
    }
  }
}

# $0: array ref for path
# $1: display prefix
# $2: don't show as deleted? (if defined, config is shown as normal instead of
#     deleted.)
sub displayDeletedOrigChildren {
  my @cur_path = @{$_[0]};
  my $prefix = $_[1];
  my $dont_show_as_deleted = $_[2];
  my $dprefix = '-';
  if (defined($dont_show_as_deleted)) {
    $dprefix = '';
  }
  $config->setLevel('');
  my @children = $config->listOrigNodes(join ' ', @cur_path);
  for my $child (sort @children) {
    if ($child eq 'node.val') {
      # should not happen!
      next;
    }
    my $is_tag = $config->isTagNode([ @cur_path, $child ]);
    $config->setLevel(join ' ', (@cur_path, $child));
    my @cnames = sort $config->listOrigNodes();
    if ($#cnames == 0 && $cnames[0] eq 'node.val') {
      displayValues([ @cur_path, $child ], $prefix, $child,
                    $dont_show_as_deleted);
    } elsif (scalar($#cnames) >= 0) {
      if ($is_tag) {
        foreach my $cname (@cnames) {
          if ($cname eq 'node.val') {
            # should not happen
            next;
          }
          print "$dprefix$prefix$child $cname {\n";
          displayDeletedOrigChildren([ @cur_path, $child, $cname ],
                                     "$prefix    ", $dont_show_as_deleted);
          print "$dprefix$prefix}\n";
        }
      } else {
        print "$dprefix$prefix$child {\n";
        displayDeletedOrigChildren([ @cur_path, $child ], "$prefix    ",
                                   $dont_show_as_deleted);
        print "$dprefix$prefix}\n";
      }
    } else {
      my $has_tmpl_children = $config->hasTmplChildren([ @cur_path, $child ]);
      print "$dprefix$prefix$child"
            . ($has_tmpl_children ? " {\n$dprefix$prefix}\n" : "\n");
    }
  }
}

# $0: hash ref for children status
# $1: array ref for path
# $2: display prefix
sub displayChildren {
  my %child_hash = %{$_[0]};
  my @cur_path = @{$_[1]};
  my $prefix = $_[2];
  for my $child (sort (keys %child_hash)) {
    if ($child eq 'node.val') {
      # should not happen!
      next;
    }
    my ($diff, $vdiff) = (' ', ' ');
    if ($child_hash{$child} eq 'added') {
      $diff = '+';
      $vdiff = '+';
    } elsif ($child_hash{$child} eq 'deleted') {
      $diff = '-';
      $vdiff = '-';
    } elsif ($child_hash{$child} eq 'changed') {
      $vdiff = '>';
    }
    my $is_tag = $config->isTagNode([ @cur_path, $child ]);
    $config->setLevel(join ' ', (@cur_path, $child));
    my %cnodes = $config->listNodeStatus();
    my @cnames = sort keys %cnodes;
    if ($#cnames == 0 && $cnames[0] eq 'node.val') {
      displayValues([ @cur_path, $child ], $prefix, $child);
    } elsif (scalar($#cnames) >= 0) {
      if ($is_tag) {
        foreach my $cname (@cnames) {
          if ($cname eq 'node.val') {
            # should not happen
            next;
          }
          my $tdiff = ' ';
          if ($cnodes{$cname} eq 'deleted') {
            $tdiff = '-';
          } elsif ($cnodes{$cname} eq 'added') {
            $tdiff = '+';
          }
          print "$tdiff$prefix$child $cname {\n";
          if ($cnodes{$cname} eq 'deleted') {
            displayDeletedOrigChildren([ @cur_path, $child, $cname ],
                                       "$prefix    ");
          } else {
            $config->setLevel(join ' ', (@cur_path, $child, $cname));
            my %ccnodes = $config->listNodeStatus();
            displayChildren(\%ccnodes, [ @cur_path, $child, $cname ],
                            "$prefix    ");
          }
          print "$tdiff$prefix}\n";
        }
      } else {
        print "$diff$prefix$child {\n";
        if ($child_hash{$child} eq 'deleted') {
          # this should not happen
          displayDeletedOrigChildren([ @cur_path, $child ], "$prefix    ");
        } else {
          displayChildren(\%cnodes, [ @cur_path, $child ], "$prefix    ");
        }
        print "$diff$prefix}\n";
      }
    } else {
      if ($child_hash{$child} eq 'deleted') {
        $config->setLevel('');
        my @onodes = $config->listOrigNodes(join ' ', (@cur_path, $child));
        if ($#onodes == 0 && $onodes[0] eq 'node.val') {
          displayValues([ @cur_path, $child ], $prefix, $child);
        } else {
          print "$diff$prefix$child {\n";
          displayDeletedOrigChildren([ @cur_path, $child ], "$prefix    ");
          print "$diff$prefix}\n";
        }
      } else {
        my $has_tmpl_children
          = $config->hasTmplChildren([ @cur_path, $child ]);
        print "$diff$prefix$child"
              . ($has_tmpl_children ? " {\n$diff$prefix}\n" : "\n");
      }
    }
  }
}

# @ARGV: represents the 'root' path. the output starts at this point under
#        the new config.
sub outputNewConfig {
  $config = new VyattaConfig;
  $config->setLevel(join ' ', @_);
  my %rnodes = $config->listNodeStatus();
  if (scalar(keys %rnodes) > 0) {
    my @rn = keys %rnodes;
    if ($#rn == 0 && $rn[0] eq 'node.val') {
      # this is a leaf value-node
      displayValues([ @_ ], '', $_[$#_]);
    } else {
      displayChildren(\%rnodes, [ @_ ], '');
    }
  } else {
    if (defined($config->existsOrig())) {
      # this is a deleted node
      print 'Configuration under "' . (join ' ', @_) . "\" has been deleted\n";
    } else {
      print "Current configuration is empty\n";
    }
  }
}

# @ARGV: represents the 'root' path. the output starts at this point under
#        the active config.
sub outputActiveConfig {
  $config = new VyattaConfig;
  $config->setLevel(join ' ', @_);
  displayDeletedOrigChildren([ @_ ], '', 1);
}

1;
