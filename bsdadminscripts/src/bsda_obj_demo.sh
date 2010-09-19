#!/bin/sh
#
# A small demo of "bsda_obj.sh", which demonstrates
# return by reference. Note that this even works
# safely when the variables within a method have the
# same names as the variables in the caller context
# (such as is the case for recursive methods).
#
# These features are really just useful byproducts
# of my desire to write object oriented shell
# scripts.
#

# Import framework.
bsda_dir="${0%${0##*/}}"
. ${bsda_dir:-.}/bsda_obj.sh

# Declare the class.
bsda:obj:createClass Demo \
	w:value \
		This is a comment \
	x:fibonacciRecursive \
		"This is a comment, too. <== my prefered style" \

#
# Implementation of the fibonacciRecursive method for the
# Demo class.
#
# Yes I know that this is the least efficient way of
# doing this, but it demonstrates what I want it to.
#
# @param 1
#	The variable to store the fibonacci value in.
# @param 2
#	The index of the fibonacci value to return.
#
Demo.fibonacciRecursive() {
	# Terminate recursion.
	if [ $2 -le 2 ]; then
		$caller.setvar "$1" 1
		return 0
	fi

	local f1 f2

	$this.fibonacciRecursive f1 $(($2 - 1))
	$this.fibonacciRecursive f2 $(($2 - 2))

	$caller.setvar "$1" $(($f1 + $f2))
}

# Create instance.
Demo demo

# Call the fibonacci method from instance and ...
# ... store the result in the value variable.
$demo.fibonacciRecursive value 8
# ... print the result.
$demo.fibonacciRecursive '' 8

# Set an attribute.
$demo.setValue $(($value - $($demo.fibonacciRecursive '' 6)))

# Get an attribute and ...
# ... store the result in the value variable.
$demo.getValue value
# ... print the attribute.
$demo.getValue

