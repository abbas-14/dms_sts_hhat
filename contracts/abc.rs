[package]
name = "eth_transfer"
version = "0.1.0"
edition = "2021"

[dependencies]
web3 = "0.16.0"
tokio = { version = "1", features = ["full"] }
ethers = { version = "1.0.0", features = ["signing"] }
reqwest = { version = "0.11", features = ["socks"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
main.rs:
Now, let's write the main.rs file, which contains the main logic for the program:
rust
Copy code
use ethers::prelude::*;
use ethers::utils::parse_units;
use std::sync::Arc;
use tokio::time::{sleep, Duration};
use web3::transports::Http;
use web3::types::{TransactionParameters, U256};
use web3::Web3;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let rpc_url = "https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID";
    let private_key: &str = "YOUR_PRIVATE_KEY_HEX";
    let recipient_address = "RECIPIENT_ADDRESS";
    let amount_in_eth = "0.01"; // amount to send

    // Proxy URLs
    let proxy_urls = vec![
        "http://proxy1:port",
        "http://proxy2:port",
        // Add more proxies as needed
    ];

    // Create tasks for each proxy URL
    let mut tasks = Vec::new();
    for proxy_url in proxy_urls {
        let rpc_url = rpc_url.to_string();
        let private_key = private_key.to_string();
        let recipient_address = recipient_address.to_string();
        let amount_in_eth = amount_in_eth.to_string();
        let proxy_url = proxy_url.to_string();

        tasks.push(tokio::spawn(async move {
            send_transaction_via_proxy(
                rpc_url,
                private_key,
                recipient_address,
                amount_in_eth,
                proxy_url,
            )
            .await
        }));
    }

    // Wait for all tasks to complete
    for task in tasks {
        task.await??;
    }

    Ok(())
}

async fn send_transaction_via_proxy(
    rpc_url: String,
    private_key: String,
    recipient_address: String,
    amount_in_eth: String,
    proxy_url: String,
) -> anyhow::Result<()> {
    // Create a proxy transport
    let client = reqwest::Client::builder()
        .proxy(reqwest::Proxy::http(&proxy_url)?)
        .build()?;

    // Create the Web3 instance
    let transport = Http::with_client(client, &rpc_url)?;
    let web3 = Web3::new(transport);

    // Get the private key
    let private_key = private_key.parse::<LocalWallet>()?;

    // Create an Ethereum address from the private key
    let from_address = private_key.address();

    // Get the nonce for the transaction
    let nonce = web3
        .eth()
        .transaction_count(from_address, None)
        .await?;

    // Get the gas price
    let gas_price = web3
        .eth()
        .gas_price()
        .await?;

    // Calculate the amount to send in Wei
    let amount = parse_units(amount_in_eth, "ether")?;

    // Create the transaction parameters
    let tx_object = TransactionParameters {
        to: Some(recipient_address.parse::<Address>()?),
        value: amount,
        gas_price: Some(gas_price),
        nonce: Some(nonce),
        ..Default::default()
    };

    // Sign the transaction
    let signed_tx = web3
        .accounts()
        .sign_transaction(tx_object, &private_key)
        .await?;

    // Send the transaction
    let result = web3
        .eth()
        .send_raw_transaction(signed_tx.raw_transaction)
        .await?;

    println!("Transaction hash: {:?}", result);

    Ok(())
}