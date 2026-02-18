# Library files
Using `boss` as the example target system:

`cat library.txt | xargs -i scp {}.sh rod@boss:/home/rod/{}.sh`

Then, `ssh boss` and:

`sudo chown root:root ts-*.sh && sudo mv ts-*.sh /usr/local/lib`

# Pogram files
**NOTE**: Change the destination path as needed.

 Using `boss` as the example target system:

`cat program.txt | xargs -i scp {}.sh rod@boss:/home/rod/`

 Then, `ssh boss` and:

`sudo chown root:root ts-*.sh && sudo chmod +x ts-*.sh && for file in ts-*.sh; do sudo mv "$file" "/usr/local/sbin/${file%.sh}"; done`
