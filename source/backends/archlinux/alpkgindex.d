/*
 * Copyright (C) 2016 Matthias Klumpp <matthias@tenstral.net>
 *
 * Licensed under the GNU Lesser General Public License Version 3
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the license, or
 * (at your option) any later version.
 *
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this software.  If not, see <http://www.gnu.org/licenses/>.
 */

module ag.backend.archlinux.pkgindex;

import std.stdio;
import std.path;
import std.string;
import std.algorithm : canFind;
static import std.file;

import ag.logging;
import ag.archive;
import ag.backend.intf;
import ag.backend.archlinux.alpkg;
import ag.backend.archlinux.listfile;


class ArchPackageIndex : PackageIndex
{

private:
    string rootDir;
    Package[][string] pkgCache;

public:

    this (string dir)
    {
        this.rootDir = dir;
        if (!std.file.exists (dir))
            throw new Exception ("Directory '%s' does not exist.", dir);
    }

    void release ()
    {
        pkgCache = null;
    }

    private void setPkgDescription (ArchPackage pkg, string pkgDesc)
    {
        if (pkgDesc is null)
            return;

        auto desc = "<p>" ~ pkgDesc ~ "</p>";
        pkg.setDescription (desc, "C");
    }

    private Package[] loadPackages (string suite, string section, string arch)
    {
        auto pkgRoot = buildPath (rootDir, suite, section, "os", arch);
        auto listsTarFname = buildPath (pkgRoot, format ("%s.files.tar.gz", section));
        if (!std.file.exists (listsTarFname)) {
            logWarning ("Package lists tarball '%s' does not exist.", listsTarFname);
            return [];
        }

        auto ad = new ArchiveDecompressor ();
        ad.open (listsTarFname);
        logDebug ("Opened: %s", listsTarFname);

        ArchPackage[string] pkgsMap;
        foreach (ref entry; ad.read ()) {

            auto archPkid = dirName (entry.fname);
            ArchPackage pkg;
            if (archPkid in pkgsMap) {
                pkg = pkgsMap[archPkid];
            } else {
                pkg = new ArchPackage ();
                pkgsMap[archPkid] = pkg;
            }

            auto infoBaseName = baseName (entry.fname);
            if (infoBaseName == "desc") {
                // we have the description file, add information to this package
                auto descF = new ListFile ();
                descF.loadData (entry.data);
                pkg.name = descF.getEntry ("NAME");
                pkg.ver  = descF.getEntry ("VERSION");
                pkg.arch = descF.getEntry ("ARCH");

                pkg.maintainer = descF.getEntry ("PACKAGER");
                pkg.filename = buildPath (pkgRoot, descF.getEntry ("FILENAME"));
                setPkgDescription (pkg, descF.getEntry ("DESC"));
            } else if (infoBaseName == "files") {
                // we found a content index, add content information to the package
                auto filesF = new ListFile ();
                filesF.loadData (entry.data);

                auto filesStr = filesF.getEntry ("FILES");
                if (filesStr is null) {
                    if (!pkg.name.canFind ("-meta")) {
                        logWarning ("Package '%s' has no file list set. Ignoring it.", pkg.toString ());
                        continue;
                    }
                }

                string[] contents;
                foreach (l; filesStr.splitLines ())
                    contents ~= "/" ~ l;
                pkg.contents = contents;
            }
        }

        // perform a sanity check, so we will never emit invalid packages
        Package[] pkgs;
        foreach (ref pkg; pkgsMap.byValue ()) {
            if (Package.isValid (pkg))
                pkgs ~= pkg;
            else
                logError ("Found an invalid package (name, architecture or version is missing). This is a bug.");
        }

        return pkgs;
    }

    Package[] packagesFor (string suite, string section, string arch)
    {
        if ((suite == "arch") || (suite == "archlinux"))
            suite = "";

        string id = suite ~ "-" ~ section ~ "-" ~ arch;
        if (id !in pkgCache) {
            auto pkgs = loadPackages (suite, section, arch);
            synchronized (this) pkgCache[id] = pkgs;
        }

        return pkgCache[id];
    }

    bool hasChanges (DataCache dcache, string suite, string section, string arch)
    {
        return true;
    }
}
