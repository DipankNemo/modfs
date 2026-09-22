"""Field counts for the colon-delimited account files, in ONE place.

Three sites parse these files for three different purposes -- reconcile.py
merges them, verify_compose.py checks the merge, 06_extract_metadata.sh records
them in the manifest -- and each declared its own copy of the field counts.

They agreed by hand, and nothing checked that they did. The cost showed up in
round 4: the SAME defect, a record with the wrong number of fields being
accepted, had to be found and fixed twice, as R4-4 in the merger and R4-6 in
the extractor, because fixing one said nothing about the other.

Only the field COUNT is shared. Which fields carry identities, which carry
member lists and which files are whole-line unions are properties of what a
caller is doing, not of the format, so those stay with their caller.
"""

# name:x:uid:gid:gecos:home:shell
# name:x:gid:members
# name:hash:lastchg:min:max:warn:inactive:expire:reserved
# name:hash:admins:members
FIELDS = {
    'etc/passwd': 7,
    'etc/group': 4,
    'etc/shadow': 9,
    'etc/gshadow': 4,
    'etc/subuid': 3,      # name:start:count
    'etc/subgid': 3,
}
