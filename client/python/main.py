from gravitino import GravitinoAdminClient


def print_metalakes(admin_client: GravitinoAdminClient) -> None:

    metalakes = admin_client.list_metalakes()
    for metalake in metalakes:
        print(f"Metalake Name: {metalake.name}")


def main():

    admin_client = GravitinoAdminClient(
        uri="http://localhost:8090",
        client_config={"gravitino_client_request_timeout": 60}
    )

    print_metalakes(admin_client)


if __name__ == "__main__":
    main()
