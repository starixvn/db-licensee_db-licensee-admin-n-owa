USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_Rpt_3rdProductWinloss] 
	@ProductCodes		VARCHAR(100)	
	, @Recommend		VARCHAR(MAX)	= ''
	, @Currency 		INT 			= 0
	, @FromDate 		SMALLDATETIME
	, @ToDate 			SMALLDATETIME	
	, @DrawFilter		SMALLINT		= 1
WITH RECOMPILE
AS
/*  
    Created: Florent.Nguyen
    Date: 2015-03-26
    Task : AG Win Loss report 
    DB: DBACC.bodb02  
    Revisions:  		
		- 20150518@Florent: Add param @DrawFilter
	Param's Explanation:  
*/
SET NOCOUNT ON

BEGIN	
	DECLARE @TempAG AS TABLE (CustID INT)	
	DECLARE @GetAll BIT = 1

	IF ISNULL(@Recommend, '') <> ''
	BEGIN
		INSERT INTO @TempAG (CustID)
		SELECT val 
		FROM dbo.strSplit(@Recommend, ',')

		SET @GetAll = 0
	END

	IF CHARINDEX('AGC', @ProductCodes) <> 0
	BEGIN
		SELECT co.recommend		
			, c.Winlostdate
			, c.Sporttype
			, c.Currency
			, SUM(c.TurnOver - CASE WHEN @DrawFilter IN (2, 3) THEN c.DrawTO ELSE 0 END) AS TurnOver
			, SUM(c.BetCount - CASE WHEN @DrawFilter IN (2) THEN c.DrawBetCount ELSE 0 END) AS TotalTrans
			, SUM(c.Winlost) AS Winloss
		FROM bodb_report.dbo.rptDepWinlost_AGCasino c WITH (NOLOCK)
			INNER JOIN dbo.Custinfo co WITH (NOLOCK) ON c.CustID = co.CustID	
		WHERE c.Winlostdate BETWEEN @FromDate AND @Todate
			AND ( @GetAll = 1 OR (@GetAll = 0 AND co.recommend IN (SELECT CustID FROM @TempAG)))
		GROUP BY co.recommend, c.Winlostdate, c.Currency, c.Sporttype		
		
		RETURN
	END

	--return metadata if params not meet
	SELECT co.recommend
		, Winlostdate
		, Sporttype
		, c.Currency
		, SUM(CAST(0 AS MONEY)) TurnOver
		, SUM(0) TotalTrans
		, SUM(CAST(0 AS MONEY)) Winloss
	FROM bodb_report.dbo.rptDepWinlost_AGCasino c WITH (NOLOCK)
		INNER JOIN dbo.Custinfo co WITH (NOLOCK) ON c.CustID = co.CustID	
	WHERE 1 != 1
	GROUP BY co.recommend, c.Winlostdate, c.Currency, c.Sporttype		
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_3rdProductWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_3rdProductWinloss] TO bodbAdminNet 