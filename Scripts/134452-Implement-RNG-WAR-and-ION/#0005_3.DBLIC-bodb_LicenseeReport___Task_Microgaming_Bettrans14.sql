/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
/*
	Created: 20200626@Parsons
	Task:   Generate data of SAG for 18/06 - Now [#FeatureID 134452]
	DB:	    DBLIC-bodb_LicenseeReport
	Remark:	Re-gen data for SAG - range bettrans14
*/

USE bodb_LicenseeReport
GO

DECLARE 
		@FromDate DATE = '2020-06-19', -- Current BU Date
		@ToDate DATE = '2020-06-21' -- Current MB Date

BEGIN
	DECLARE @ErrMsg VARCHAR(200)

	DECLARE @WinlostDate DATE
	SELECT	@WinlostDate = @FromDate

	WHILE @WinlostDate <= @ToDate
	BEGIN
		SELECT @ErrMsg = 'WinlostDate=' + CONVERT(VARCHAR(20), @WinlostDate, 120)
		RAISERROR(@ErrMsg, 1, 0) WITH NOWAIT

		EXEC dbo.Task_Microgaming_Bettrans14 @FromDate = @WinlostDate, @ToDate = @WinlostDate

		--reset params
		SET @WinlostDate = DATEADD(DAY, 1, @WinlostDate)

		WAITFOR DELAY '00:00:00.280'
	END
END
GO