from typing import Dict
import os
import shutil


def copy_files_to_dir(file_paths, dir_path) -> Dict[str, str]:
    """
    Return:
        {source_path: copy_tmp_path}
    """
    file_map = {}

    for file_path in file_paths:
        if not os.path.exists(file_path):
            continue

        file_name = str(file_path).replace(str(os.path.sep), "@@").replace(" ", "_")
        dest_path = os.path.join(dir_path, file_name)
        shutil.copy2(file_path, dest_path)
        file_map[file_path] = dest_path
    return file_map
