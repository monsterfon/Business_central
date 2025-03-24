# Item Classification Extension for Microsoft Dynamics Business Central

## Overview
This project implements functionality for classifying items in Microsoft Dynamics Business Central. It introduces a new "Item Class" table, a page for managing item classes, and modifications to the existing Item table and Item Card to incorporate item classification.

## Features
- **Item Class Table**: A new table that stores item classes with fields for Code, Description, and Unit Price Increase (%).
- **Item Class Management Page**: A user-friendly page for viewing, adding, modifying, and deleting item classes.
- **Item Table Extension**: Extends the existing Item table to include a new field for Item Class, with validation logic based on the Blocked status of the item.
- **Item Card Extension**: Enhances the Item Card to display the new Item Class field and includes validation to prevent selection of a class for blocked items.

## Setup Instructions
1. Clone the repository to your local machine.
2. Open the project in your AL development environment.
3. Ensure you have the necessary permissions and access to deploy extensions in your Business Central environment.
4. Publish the extension to your Business Central instance.

## Additional Information
For any issues or feature requests, please refer to the project's issue tracker. Contributions are welcome! Please follow the contribution guidelines outlined in the repository.