/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
/*
	Created: 20210113@Parsons
	Task:   Generate data of Joker for 2020-11-12 -> Now [#FeatureID 148617]
	DB:	    DBLIC-bodb_LicenseeReport
	Remark:	Re-gen data for Joker - range bettrans14
*/

USE bodb_LicenseeReport
GO

DECLARE 
		@FromDate DATE = '2021-01-08', -- Current BU Date
		@ToDate DATE = '2021-01-10' -- Current MB Date

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