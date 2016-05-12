/*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : Allbetclub
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'Allbetclub',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-03',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 4000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-03',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-03',
 @Todate = '2050-01-01', 
 @Rate = 0.07

/*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : AG
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'AG',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-03',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 5000,
 @MinFeeCurrencyID = 6

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-03',
 @Todate = '2050-01-01', 
 @Rate = 0.07

/*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : THBET
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'THBET',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-03',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 4000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-03',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-03',
 @Todate = '2050-01-01', 
 @Rate = 0.07

/*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : 28bet
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = '28bet',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-04',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 4000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-04',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-04',
 @Todate = '2050-01-01', 
 @Rate = 0.07

 --VS 
exec dbo.OAS_addProductToParty
 @ProductName = 'VS',
 @FromParty = @LicName,
 @ToParty = @Company, 
 @Fromdate = '2014-06-19',
 @Todate = '2050-01-01', 
 @Rate = 0.15

/*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : Honbet
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'Honbet',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-05',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 5000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-05',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-05',
 @Todate = '2050-01-01', 
 @Rate = 0.07

 /*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : 9Club
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = '9Club',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-10',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 5000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-10',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-10',
 @Todate = '2050-01-01', 
 @Rate = 0.07

 --VS default
 exec dbo.OAS_addProductToParty
 @ProductName = 'VS',
 @FromParty = @LicName,
 @ToParty = @Company, 
 @Fromdate = '2014-06-10',
 @Todate = '2050-01-01', 
 @Rate = 0.15

/*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : iBET
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'iBET',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-13',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 5000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-13',
 @Todate = '2050-01-01', 
 @Rate = 0.15

 --VS default
 exec dbo.OAS_addProductToParty
 @ProductName = 'VS',
 @FromParty = @LicName,
 @ToParty = @Company, 
 @Fromdate = '2014-06-13',
 @Todate = '2050-01-01', 
 @Rate = 0.15


/*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : BE7
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'BE7',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-30',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 4000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-30',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-06-30',
 @Todate = '2050-01-01', 
 @Rate = 0.07

 /*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : Q8bola
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'Q8bola',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-09-01',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 2500,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-09-01',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--LC
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-09-01',
 @Todate = '2050-01-01', 
 @Rate = 0.07

 /*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : DAYWIN
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'DAYWIN',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-09-17',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 5000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-09-17',
 @Todate = '2050-01-01', 
 @Rate = 0.15

--VS default
exec dbo.OAS_addProductToParty
 @ProductName = 'VS',
 @FromParty = @LicName,
 @ToParty = @Company, 
 @Fromdate = '2014-09-17',
 @Todate = '2050-01-01', 
 @Rate = 0.15

 /*
    Author: Florent.Nguyen
    Date : 2014-10-17
    Task: Add licensee and product to Licensee Admin system
    Target Licensee : Royalebet
*/
USE bodb_licensee
GO
DECLARE @LicName	NVARCHAR (20) = 'Royalebet',
	   @Company	NVARCHAR (20) = 'Boping'
--SB
exec dbo.OAS_addProductToParty
 @ProductName = 'SB',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-04-28',
 @Todate = '2050-01-01', 
 @Rate = 1,
 @Minfee = 4000,
 @MinFeeCurrencyID = 6

--NG
 exec dbo.OAS_addProductToParty
 @ProductName = 'NG',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-04-28',
 @Todate = '2050-01-01', 
 @Rate = 0.15


 --LC 
exec dbo.OAS_addProductToParty
 @ProductName = 'LC',
 @FromParty = @LicName,
 @ToParty = @Company,
 @Fromdate = '2014-04-28',
 @Todate = '2050-01-01', 
 @Rate = 0.07