/*<info serverAlias="DBLIC-bodb_Licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER FUNCTION [dbo].[LA_f_BaseCurrency]()
	RETURNS @tbBaseCurrency TABLE (CurrencyId INT,CurrencyName VARCHAR(10), Description VARCHAR(100))
AS  
/*
	Created: 20150312@Florent
	Task : Get list Base currency
	DB: DB052/bodb_Licensee
	Revisions:
		- 20190820@Bruce: Restore SP [#111586]
*/  
BEGIN
 INSERT INTO @tbBaseCurrency(CurrencyId, CurrencyName, [Description])  
 SELECT e.exchangeid, e.Code, e.Description  
 FROM bodb02.dbo.Exchange e WITH (NOLOCK)  
 WHERE e.Code IN   
 (  
    'CNY' -- ExchangeID = 13  
  , 'EUR' -- ExchangeID = 6    
  , 'GBP' -- ExchangeID = 12  
  , 'USD' -- ExchangeID = 3    
 )  
  AND e.exchangeid IN  
 (  
    3  
  , 6  
  , 12  
  , 13  
 )  
      
 RETURN  
END  