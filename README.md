# Aptos Network Reward Contract

This repository contains the reward smart contract for the Aptos Network. The setup instructions can be found in the [Aptos Network tutorials](https://aptos.dev/tutorials/build-e2e-dapp/create-a-smart-contract/).

## Overview

The smart contract serves as a reward system where an admin user (deploying address) can create organizations, events, and tickets. The workflow follows these steps:

1. **Create Organization**: Admin user creates an organization.
2. **Create Event**: Using an organization object, an event is created.
3. **Create Ticket**: Using the event object, a ticket is created.

Tickets are associated with ticket types, and these types can be randomized using the Aptos Framework.

## Randomization of Ticket Types

The contract provides two functions for randomizing ticket types:

- **create_random_ticket**: This function utilizes the random framework from Aptos to randomize ticket types based on admin input. Admin should enter comma-separated input for the `ticket_types` parameter, which is a vector of strings. For example, entering `1,2,3,4,5` as input will assign the ticket a random type between 1 and 5.
  
- **create_weighted_random_ticket**: Similar to `create_random_ticket`, this function also includes a weighing mechanism for ticket types.

## Usage

To use the contract, follow the setup instructions provided in the [Aptos Network tutorials](https://aptos.dev/tutorials/build-e2e-dapp/create-a-smart-contract/). 

The contract is currently in use by Nameless Youth Club, accessible at [https://random.nameless-beta.com](https://random.nameless-beta.com).

## About Aptos Network

Aptos Network is a decentralized platform for building end-to-end decentralized applications (DApps). For more information about Aptos and its ecosystem, visit [https://aptos.dev](https://aptos.dev).


