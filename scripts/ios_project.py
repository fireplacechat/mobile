"""Read Xcode's OpenStep property list without a third-party parser."""
import json
import re


def parse_project(source):
    pattern = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+')
    tokens = [t for t in pattern.findall(source) if not t.startswith(('//', '/*'))]
    position = 0

    def take():
        nonlocal position
        if position >= len(tokens):
            raise ValueError('Truncated project')
        token = tokens[position]
        position += 1
        return token

    def expect(token):
        if take() != token:
            raise ValueError('Invalid project structure')

    def value():
        token = take()
        if token == '{':
            result = {}
            while tokens[position] != '}':
                key = value()
                if not isinstance(key, str) or key in result:
                    raise ValueError('Duplicate or invalid project key')
                expect('=')
                result[key] = value()
                expect(';')
            expect('}')
            return result
        if token == '(':
            result = []
            while tokens[position] != ')':
                result.append(value())
                if tokens[position] != ')':
                    expect(',')
            expect(')')
            return result
        if token in '})=;,':
            raise ValueError('Unexpected project token')
        return json.loads(token) if token.startswith('"') else token

    result = value()
    if position != len(tokens):
        raise ValueError('Trailing project data')
    return result
