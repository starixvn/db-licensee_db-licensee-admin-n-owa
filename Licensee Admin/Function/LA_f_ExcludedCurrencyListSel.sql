/*<info serverAlias="DBLIC-bodb_Licensee,DBCUST-bodb_Licensee,DBACC-bodb_licensee" selecters="wsv_nap,wsv_lap" isFunction="1" isNested="1"></info>*/
USE bodb_Licensee
GO

CREATE FUNCTION [dbo].[LA_f_ExcludedCurrencyListSel] 
()
RETURNS TABLE 
AS
/*	Created: 20240924@Danny
	Task : Select list of excluded Currency
	DB: DBLIC.bodb_Licensee, DBCUST-bodb_Licensee,DBACC-bodb_licensee
	
	Revisions:
		- 20240924@Danny: Initialize function [#210422]  

	SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x
		
*/

RETURN
	SELECT CAST (20 AS INT)  AS ExchangeID -- UUS
	UNION ALL
	SELECT 218 -- BTS
	
	
GO