/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20230529@Danny
	DB: DBCUST-bodb_Licensee
	Task: Remove unused setting
*/
USE bodb_Licensee
GO

--  Base Curr
DELETE FROM OAS_PartyBaseCurrency WITH(ROWLOCK)
WHERE 
	(PartyID IN (554,679,859) AND BaseCurrencyId = 6) -- 442ball, BBSPORTS, ZFRT142 EUR
		OR 
	(PartyID = 794 AND BaseCurrencyId = 142) -- HX9Candy USDT


-- MF
DELETE FROM LA_Minfee WITH(ROWLOCK) WHERE FeeTypeID = 1 AND 
  (
    (partyID = 794 AND CurrencyID = 142) -- HX9Candy USDT
		OR 
	(partyID = 554 AND CurrencyID = 6) -- ZFRT142 EUR
   )
