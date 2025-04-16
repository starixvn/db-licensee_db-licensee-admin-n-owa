/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[SH_SabaPlay_BaseCurrencySel]	
AS
/*
	Created: 20150416@Danny
	Task : Get all BaseCurrency
	DB: DB052.bodb_licensee
	
	Revisions:
		- 20150416@Danny: create SP
		
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT 96 AS CurrencyId, 'USD (USDT)' CurrencyName
	
END
GO