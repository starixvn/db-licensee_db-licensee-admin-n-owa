/*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : 88Macao
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = '88Macao',
	   @Company	NVARCHAR (20) = 'Boping' 
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-01-06',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 5000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-01-06',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-01-06',
 @Todate = '2050-01-01', 
 @Rate = 0.07

 /*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : 67BET
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = '67BET',
	   @Company	NVARCHAR (20) = 'Boping' 
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-02-06',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 5000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-02-06',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-02-06',
 @Todate = '2050-01-01', 
 @Rate = 0.07

 /*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : HBOBet
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'HBOBet',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-03-03',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 4000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-03-03',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-03-03',
 @Todate = '2050-01-01', 
 @Rate = 0.07

 /*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : Winner99
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'Winner99',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-03-03',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 4000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-03-03',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-03-03',
 @Todate = '2050-01-01', 
 @Rate = 0.07


 /*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : Mgm88
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'Mgm88',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-03-03',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 4000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-03-03',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-03-03',
 @Todate = '2050-01-01', 
 @Rate = 0.07

 /*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : Ae88
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'Ae88',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-04-08',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 5000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-04-08',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-04-08',
 @Todate = '2050-01-01', 
 @Rate = 0.07

 /*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : M8bola
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'M8bola',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-05-29',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 2500,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-05-29',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-05-29',
 @Todate = '2050-01-01', 
 @Rate = 0.07