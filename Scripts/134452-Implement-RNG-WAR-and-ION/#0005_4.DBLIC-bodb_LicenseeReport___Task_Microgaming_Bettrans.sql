/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
/*
	Created: 20200626@Parsons
	Task:   Generate data of SAG for 01/06 - Now [#FeatureID 134452]
	DB:	    DBLIC-bodb_LicenseeReport
	Remark:	Re-gen data for SAG - range bettrans
*/

USE bodb_LicenseeReport
GO

DECLARE 
		@FromDate DATE = '2020-06-22', -- Current MB Date + 1
		@ToDate	DATE = '2020-06-26' -- Current Date

BEGIN
	DECLARE @ErrMsg VARCHAR(200)

	DECLARE @WinlostDate DATE
	SELECT	@WinlostDate = @FromDate

	WHILE @WinlostDate <= @ToDate
	BEGIN
		SELECT @ErrMsg = 'WinlostDate=' + CONVERT(VARCHAR(20), @WinlostDate, 120)
		RAISERROR(@ErrMsg, 1, 0) WITH NOWAIT

		EXEC dbo.Task_Microgaming_Bettrans @WinlossDate = @WinlostDate

		--reset params
		SET @WinlostDate = DATEADD(DAY, 1, @WinlostDate)

		WAITFOR DELAY '00:00:00.280'
	END
END
GO