/**
 * Consignment products: the products a supplier can send directly to the
 * customer (494). A page of its own since 8 Nov 2026 (the user), where it was a
 * tab of Special & Rentals: the same list, columns and product form, and no
 * tabs or waiting list. A paid sale of one still waits on Special & Rentals,
 * where the supplier is chosen, and is listed on its Sales tab.
 */
import React from 'react';
import SpecialPage from './SpecialPage';

const ConsignmentPage: React.FC = () => <SpecialPage view="consignment" />;

export default ConsignmentPage;
