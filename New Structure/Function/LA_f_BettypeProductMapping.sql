USE [bodb_licensee]
GO
/****** Object:  UserDefinedFunction [dbo].[LA_f_BettypeProductMapping]    Script Date: 01/12/2014 14:32:00 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER FUNCTION [dbo].[LA_f_BettypeProductMapping] (
	 @Bettype	 	INT = 0
	,@ProductCodes VARCHAR(1000)	
	)
RETURNS @tbBettypeProduct TABLE (
	Bettype INT,ProductID INT
	)
AS
/*  Created: 20141111@Florent  
    Task : Get bettype product mapping
    DB: DB052/bodb_Licensee  
    Param's Explanation:   

*/

BEGIN
    IF CHARINDEX('SB', @ProductCodes) <> 0
	   --OR CHARINDEX('BA', @ProductCodes) <> 0
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 0
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE (typeid < 31
		  OR typeid BETWEEN 121 AND 999
		  OR typeid BETWEEN 1301 AND 1399)
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

    IF CHARINDEX('BA', @ProductCodes) <> 0
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 3
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE (typeid < 31
		  OR typeid BETWEEN 121 AND 999
		  OR typeid BETWEEN 1301 AND 1399)
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

    IF CHARINDEX('RB', @ProductCodes) <> 0
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 1
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 31 AND 33
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

    IF CHARINDEX('NG', @ProductCodes) <> 0
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 2
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 81 AND 120
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

    IF CHARINDEX('LC', @ProductCodes) <> 0
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 4
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1101 AND 1199
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

    IF CHARINDEX('VS', @ProductCodes) <> 0
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 5
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1201 AND 1299
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

    IF CHARINDEX('CS', @ProductCodes) <> 0
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 6
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid = 71
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	RETURN
END
