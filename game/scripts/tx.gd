class_name Tx
extends RefCounted
## Translation helpers usable anywhere (static code included). See scripts/lang.gd.

## Translate one piece of text (unknown text comes back unchanged).
static func s(text) -> String:
	if not text is String and not text is StringName:
		return str(text)
	var t := String(text)
	var out := String(TranslationServer.translate(t))
	if out != t or t == "":
		return out
	# composite names built in code ("Copacabana Gi" + " Jacket"): translate the parts
	for suf in SUFFIXES:
		if t.length() > suf.length() and t.ends_with(suf):
			var base := t.substr(0, t.length() - suf.length())
			var tb := String(TranslationServer.translate(base))
			if tb != base:
				return tb + String(TranslationServer.translate(suf))
	return out

const SUFFIXES := [" Jacket", " Pants", " Belt", " Boss"]

## Translate a format pattern and its text arguments, then format: Tx.f("Beat %s", [name]).
static func f(pattern: String, args = []) -> String:
	var a: Array = args if args is Array else [args]
	var out: Array = []
	for x in a:
		out.append(s(x) if x is String or x is StringName else x)
	return s(pattern) % out

## For a Label's text: keep exact keys as they are (Godot translates those live, so they follow
## a language switch), and only pre-translate composite names that have no key of their own.
static func disp(text: String) -> String:
	if text == "" or String(TranslationServer.translate(text)) != text:
		return text
	return s(text)
