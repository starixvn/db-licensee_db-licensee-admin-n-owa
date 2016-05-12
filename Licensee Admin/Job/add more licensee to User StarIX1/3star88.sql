/*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : 3star88
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = '3star88',
	   @Company	NVARCHAR (20) = 'Boping' 
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2013-09-30',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 5000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2013-09-30',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2013-09-30',
 @Todate = '2050-01-01', 
 @Rate = 0.07