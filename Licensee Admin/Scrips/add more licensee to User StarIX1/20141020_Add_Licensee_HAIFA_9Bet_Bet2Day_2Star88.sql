USE bodb_licensee
GO
/*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : HAIFA
*/
DECLARE @LicName	NVARCHAR (20) = 'HAIFA',
	   @Company	NVARCHAR (20) = 'Oneworks' 
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2011-09-01',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 5000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2013-09-09',
 @Todate = '2050-01-01', 
 @Rate = 0.075

--VS
 exec dbo.OAS_addProductToParty
 @ProductName = 'VS',
 @FromParty = @LicName,
 @ToParty = @Company,
 @ParentChargeID = 217,
 @Fromdate = '2014-06-13',
 @Todate = '2050-01-01', 
 @Rate = 0.15

 /*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : 9Bet
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = '9Bet',
	   @Company	NVARCHAR (20) = 'Boping' 
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2013-08-09',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 4000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2013-08-09',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2013-08-09',
 @Todate = '2050-01-01', 
 @Rate = 0.07

 /*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : Bet2day
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'Bet2day',
	   @Company	NVARCHAR (20) = 'Boping' 
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2013-09-16',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 4000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2013-09-16',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2013-09-16',
 @Todate = '2050-01-01', 
 @Rate = 0.07

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
