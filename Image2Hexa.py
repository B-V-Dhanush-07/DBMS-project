import os

def png_to_hex(file_path):
    with open(file_path, "rb") as file:
        image_bytes = file.read()

    return image_bytes.hex()


def main():
    folder_path = "images"
    file_name = "image.png"  # Replace with your PNG filename

    file_path = os.path.join(folder_path, file_name)

    if not os.path.isfile(file_path):
        print("Error: PNG file not found:", file_path)
        return

    hex_code = png_to_hex(file_path)

    print("Hexadecimal code:")
    print(hex_code)

    # Save the hexadecimal code to a text file
    output_path = os.path.join(folder_path, "image_hex.txt")

    with open(output_path, "w") as file:
        file.write(hex_code)

    print("\nHexadecimal code saved to:", output_path)


if __name__ == "__main__":
    main()
